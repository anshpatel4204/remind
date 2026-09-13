import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/reminder_data_source.dart';
import 'package:remind/data/datasources/settings_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';
import 'package:remind/data/repositories/reminder_repository.dart';
import 'package:remind/data/repositories/settings_repository.dart';
import 'package:remind/data/repositories/task_repository.dart';
import 'package:remind/services/notification/notification_scheduler.dart';
import 'package:remind/services/notification/notification_transport.dart';
import 'package:remind/services/reminder/reminder_engine.dart';

import '../../test_helpers/fake_notification_transport.dart';
import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late TaskRepository taskRepository;
  late ReminderRepository reminderRepository;
  late RecurrenceRepository recurrenceRepository;
  late ReminderEngine reminderEngine;
  late SettingsRepository settingsRepository;
  late FakeNotificationTransport transport;
  late NotificationScheduler scheduler;

  setUp(() {
    testDb = TestAppDatabase.create();
    taskRepository = TaskRepository(
      TaskDataSource(testDb.appDatabase),
      TaskTagDataSource(testDb.appDatabase),
    );
    reminderRepository = ReminderRepository(ReminderDataSource(testDb.appDatabase));
    recurrenceRepository = RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
    reminderEngine = ReminderEngine(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      recurrenceRepository: recurrenceRepository,
    );
    settingsRepository = SettingsRepository(SettingsDataSource(testDb.appDatabase));
    transport = FakeNotificationTransport();
    scheduler = NotificationScheduler(
      transport: transport,
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      reminderEngine: reminderEngine,
      settingsRepository: settingsRepository,
    );
  });

  tearDown(() => testDb.tearDown());

  group('scheduling', () {
    test('schedules a one-time notification carrying the task title/description/time/actions', () async {
      final task = await taskRepository.createTask(
        title: 'Pay rent',
        description: 'Due at the start of the month',
      );

      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      final scheduled = transport.scheduled[reminder.id];
      expect(scheduled, isNotNull);
      expect(scheduled!.title, 'Pay rent');
      expect(scheduled.body, 'Due at the start of the month');
      expect(scheduled.scheduledTime, DateTime(2026, 9, 15, 9, 0));
      expect(scheduled.actions.map((a) => a.id), [
        NotificationActionIds.complete,
        NotificationActionIds.snooze,
        NotificationActionIds.dismiss,
      ]);
      expect(scheduled.payload, reminder.id.toString());

      // The reminder's own row mirrors the id its notification was
      // scheduled under.
      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted?.notificationId, reminder.id);
    });

    test('multiple reminders schedule independently under distinct ids', () async {
      final taskA = await taskRepository.createTask(title: 'Task A');
      final taskB = await taskRepository.createTask(title: 'Task B');

      final reminderA = await scheduler.createAndScheduleReminder(
        taskId: taskA.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );
      final reminderB = await scheduler.createAndScheduleReminder(
        taskId: taskB.id!,
        reminderTime: DateTime(2026, 9, 16, 10, 0),
      );

      expect(reminderA.id, isNot(reminderB.id));
      expect(transport.scheduled.keys, containsAll(<int>[reminderA.id!, reminderB.id!]));
      expect(transport.scheduled[reminderA.id]!.title, 'Task A');
      expect(transport.scheduled[reminderB.id]!.title, 'Task B');
    });
  });

  group('cancel / reschedule (duplicate prevention)', () {
    test('cancelReminder cancels the notification and disables the reminder row', () async {
      final task = await taskRepository.createTask(title: 'Water plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.cancelReminder(reminder.id!);

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted?.isEnabled, isFalse);
    });

    test('rescheduling cancels the old notification before scheduling the new one', () async {
      final task = await taskRepository.createTask(title: 'Call the bank');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );
      transport.calls.clear();

      await scheduler.updateAndRescheduleReminder(reminder.id!, DateTime(2026, 9, 16, 9, 0));

      expect(transport.calls, ['cancel:${reminder.id}', 'schedule:${reminder.id}']);
      // Exactly one notification remains for this reminder - never two.
      expect(transport.scheduled.keys.where((id) => id == reminder.id), hasLength(1));
      expect(transport.scheduled[reminder.id]!.scheduledTime, DateTime(2026, 9, 16, 9, 0));
    });
  });

  group('snooze presets', () {
    final now = DateTime(2026, 9, 15, 9, 0);

    Future<int> createReminder() async {
      final task = await taskRepository.createTask(title: 'Take a break');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: now,
      );
      return reminder.id!;
    }

    test('5/10/15/30 minutes and 1 hour add a fixed duration', () async {
      final cases = <SnoozeOption, Duration>{
        SnoozeOption.fiveMinutes: const Duration(minutes: 5),
        SnoozeOption.tenMinutes: const Duration(minutes: 10),
        SnoozeOption.fifteenMinutes: const Duration(minutes: 15),
        SnoozeOption.thirtyMinutes: const Duration(minutes: 30),
        SnoozeOption.oneHour: const Duration(hours: 1),
      };

      for (final entry in cases.entries) {
        final reminderId = await createReminder();
        final snoozed = await scheduler.snoozeReminder(reminderId, option: entry.key, now: now);
        expect(snoozed?.snoozedUntil, now.add(entry.value), reason: '${entry.key}');
        expect(transport.scheduled[reminderId]!.scheduledTime, now.add(entry.value));
      }
    });

    test('tomorrow snoozes to the same time on the next calendar day', () async {
      final reminderId = await createReminder();
      final snoozed = await scheduler.snoozeReminder(
        reminderId,
        option: SnoozeOption.tomorrow,
        now: now,
      );
      expect(snoozed?.snoozedUntil, DateTime(2026, 9, 16, 9, 0));
    });

    test('custom uses the caller-supplied duration', () async {
      final reminderId = await createReminder();
      final snoozed = await scheduler.snoozeReminder(
        reminderId,
        option: SnoozeOption.custom,
        customDuration: const Duration(hours: 3),
        now: now,
      );
      expect(snoozed?.snoozedUntil, now.add(const Duration(hours: 3)));
    });

    test('custom without a duration is rejected', () async {
      final reminderId = await createReminder();
      expect(
        () => scheduler.snoozeReminder(reminderId, option: SnoozeOption.custom, now: now),
        throwsArgumentError,
      );
    });

    test('snoozing cancels the previous notification and reschedules under the same id', () async {
      final reminderId = await createReminder();
      transport.calls.clear();

      await scheduler.snoozeReminder(reminderId, option: SnoozeOption.tenMinutes, now: now);

      expect(transport.calls, ['cancel:$reminderId', 'schedule:$reminderId']);
    });
  });

  group('permission handling', () {
    test('does not prompt when notifications are already enabled', () async {
      transport.notificationsEnabled = true;
      final result = await scheduler.ensureNotificationPermission();
      expect(result, isTrue);
    });

    test('requests permission when not yet enabled, and reflects a denial', () async {
      transport.notificationsEnabled = false;
      transport.grantPermissionOnRequest = false;

      final result = await scheduler.ensureNotificationPermission();

      expect(result, isFalse);
    });

    test('requests permission when not yet enabled, and reflects a grant', () async {
      transport.notificationsEnabled = false;
      transport.grantPermissionOnRequest = true;

      final result = await scheduler.ensureNotificationPermission();

      expect(result, isTrue);
    });
  });

  group('notification actions', () {
    test('Complete on a non-recurring task cancels its notification and completes the task', () async {
      final task = await taskRepository.createTask(title: 'Read a chapter');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.handleInteraction(
        NotificationInteraction(
          notificationId: reminder.id!,
          actionId: NotificationActionIds.complete,
        ),
      );

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.completed);
    });

    test('Complete on a recurring task reschedules the reminder for the next occurrence', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 9, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 9, 0),
      );
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 9, 0),
      );

      await scheduler.handleInteraction(
        NotificationInteraction(
          notificationId: reminder.id!,
          actionId: NotificationActionIds.complete,
        ),
      );

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.pending);
      expect(persistedTask?.dueDate, DateTime(2026, 1, 2, 9, 0));

      // The same reminder id is still the one scheduled - rolled forward,
      // not duplicated.
      expect(transport.scheduled[reminder.id]!.scheduledTime, DateTime(2026, 1, 2, 9, 0));
    });

    test('Snooze applies the default duration', () async {
      final task = await taskRepository.createTask(title: 'Stretch');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.handleInteraction(
        NotificationInteraction(notificationId: reminder.id!, actionId: NotificationActionIds.snooze),
      );

      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted?.snoozeMinutes, isNotNull);
      expect(persisted?.snoozedUntil, isNotNull);
    });

    test('Dismiss cancels the notification without completing the task', () async {
      final task = await taskRepository.createTask(title: 'Something optional');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.handleInteraction(
        NotificationInteraction(notificationId: reminder.id!, actionId: NotificationActionIds.dismiss),
      );

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.pending);
    });

    test('a plain tap (no action) leaves the notification and task untouched', () async {
      final task = await taskRepository.createTask(title: 'Just a tap');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.handleInteraction(NotificationInteraction(notificationId: reminder.id!));

      expect(transport.scheduled.containsKey(reminder.id), isTrue);
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.pending);
    });

    test('routes through the transport-registered callback exactly as the OS would deliver it', () async {
      await scheduler.initialize();
      final task = await taskRepository.createTask(title: 'Via callback');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await transport.simulateInteraction(
        NotificationInteraction(notificationId: reminder.id!, actionId: NotificationActionIds.dismiss),
      );

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
    });
  });

  group('task-level operations', () {
    test('completeTask cancels the notification for every reminder on that task', () async {
      final task = await taskRepository.createTask(title: 'Multi-reminder task');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.completeTask(task.id!);

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.completed);
    });

    test('cancelNotificationsForTask cancels without touching the reminder row', () async {
      final task = await taskRepository.createTask(title: 'About to be deleted');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await scheduler.cancelNotificationsForTask(task.id!);

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
      // The row itself is untouched here - deleting it is the caller's
      // separate responsibility (see tasks_screen.dart).
      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted, isNotNull);
    });
  });

  group('startup reconciliation', () {
    test('schedules an enabled, future reminder missing from pending notifications', () async {
      final task = await taskRepository.createTask(title: 'Missed by the OS');
      final reminder = await reminderRepository.createReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );
      // Deliberately never scheduled via the scheduler, to simulate drift.
      expect(transport.scheduled.containsKey(reminder.id), isFalse);

      await scheduler.reconcileAfterStartup(now: DateTime(2026, 9, 15));

      expect(transport.scheduled.containsKey(reminder.id), isTrue);
    });

    test('does not schedule a reminder whose time has already passed', () async {
      final task = await taskRepository.createTask(title: 'Missed entirely');
      final reminder = await reminderRepository.createReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 9, 0),
      );

      await scheduler.reconcileAfterStartup(now: DateTime(2026, 9, 15));

      expect(transport.scheduled.containsKey(reminder.id), isFalse);
    });

    test('a recurring reminder missed for days catches up to the next future '
        'occurrence and schedules that instead of every missed one', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await reminderRepository.createReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      // Inactive from Jan 1st through Jan 6th - never restarted, never
      // scheduled, five daily occurrences missed.
      await scheduler.reconcileAfterStartup(now: DateTime(2026, 1, 6, 12, 0));

      // Exactly one notification is scheduled - for the next valid future
      // occurrence, not a backlog of the missed ones.
      expect(transport.scheduled.length, 1);
      final scheduled = transport.scheduled[reminder.id]!;
      expect(scheduled.scheduledTime, DateTime(2026, 1, 7, 8, 0));

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.dueDate, DateTime(2026, 1, 7, 8, 0));
    });

    test('a recurring reminder whose recurrence ended during the missed time '
        'is disabled rather than left stuck in the past', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
        endDate: DateTime(2026, 1, 3, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Short course of medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await reminderRepository.createReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      await scheduler.reconcileAfterStartup(now: DateTime(2026, 1, 10, 0, 0));

      expect(transport.scheduled, isEmpty);
      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.isEnabled, isFalse);
    });

    test('cancels a stray pending notification with no matching enabled reminder', () async {
      // Nothing in the database corresponds to this id - as if a reminder
      // had been deleted by some path that didn't go through the
      // scheduler.
      await transport.schedule(
        id: 424242,
        title: 'Orphaned',
        scheduledTime: DateTime(2026, 9, 20),
        actions: const [],
      );

      await scheduler.reconcileAfterStartup(now: DateTime(2026, 9, 15));

      expect(transport.scheduled.containsKey(424242), isFalse);
    });
  });

  group('in-app notification settings', () {
    test('sound/vibration default to on and are passed through to the transport', () async {
      expect(await scheduler.soundEnabled(), isTrue);
      expect(await scheduler.vibrationEnabled(), isTrue);

      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );

      final scheduled = transport.scheduled[reminder.id]!;
      expect(scheduled.soundEnabled, isTrue);
      expect(scheduled.vibrationEnabled, isTrue);
    });

    test('turning sound/vibration off is reflected in the next scheduled notification', () async {
      await scheduler.setSoundEnabled(false);
      await scheduler.setVibrationEnabled(false);

      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );

      final scheduled = transport.scheduled[reminder.id]!;
      expect(scheduled.soundEnabled, isFalse);
      expect(scheduled.vibrationEnabled, isFalse);
    });

    test('the master switch defaults to on', () async {
      expect(await scheduler.notificationsMasterEnabled(), isTrue);
    });

    test('turning the master switch off cancels everything and stops new scheduling', () async {
      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );
      expect(transport.scheduled, isNotEmpty);

      await scheduler.setNotificationsMasterEnabled(false);
      expect(transport.scheduled, isEmpty);

      // The reminder row itself is untouched - only the platform
      // notification is suppressed.
      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted, isNotNull);
      expect(persisted!.isEnabled, isTrue);

      // A brand new reminder also does not reach the platform while off.
      final another = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 21, 9, 0),
      );
      expect(transport.scheduled.containsKey(another.id), isFalse);
    });

    test('turning the master switch back on re-schedules what should be active', () async {
      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );

      await scheduler.setNotificationsMasterEnabled(false);
      expect(transport.scheduled, isEmpty);

      await scheduler.setNotificationsMasterEnabled(true);
      expect(transport.scheduled.containsKey(reminder.id), isTrue);
    });

    test('default snooze option defaults to 10 minutes and is used by the notification Snooze action', () async {
      await scheduler.initialize();
      expect(await scheduler.defaultSnoozeOption(), SnoozeOption.tenMinutes);

      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );

      await transport.simulateInteraction(
        NotificationInteraction(notificationId: reminder.id!, actionId: NotificationActionIds.snooze),
      );

      final snoozed = await reminderRepository.getReminder(reminder.id!);
      expect(snoozed?.snoozeMinutes, 10);
    });

    test('changing the default snooze option changes what the notification Snooze action applies', () async {
      await scheduler.initialize();
      await scheduler.setDefaultSnoozeOption(SnoozeOption.thirtyMinutes);

      final task = await taskRepository.createTask(title: 'Water the plants');
      final reminder = await scheduler.createAndScheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 20, 9, 0),
      );

      await transport.simulateInteraction(
        NotificationInteraction(notificationId: reminder.id!, actionId: NotificationActionIds.snooze),
      );

      final snoozed = await reminderRepository.getReminder(reminder.id!);
      expect(snoozed?.snoozeMinutes, 30);
    });
  });
}
