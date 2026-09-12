import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/reminder_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/recurrence_repository.dart';
import 'package:remind/data/repositories/reminder_repository.dart';
import 'package:remind/data/repositories/task_repository.dart';
import 'package:remind/services/reminder/reminder_engine.dart';

import '../../test_helpers/test_database_factory.dart';

void main() {
  setUpAll(initTestSqfliteFfi);

  late TestAppDatabase testDb;
  late TaskRepository taskRepository;
  late ReminderRepository reminderRepository;
  late RecurrenceRepository recurrenceRepository;
  late ReminderEngine engine;

  setUp(() {
    testDb = TestAppDatabase.create();
    taskRepository = TaskRepository(
      TaskDataSource(testDb.appDatabase),
      TaskTagDataSource(testDb.appDatabase),
    );
    reminderRepository = ReminderRepository(ReminderDataSource(testDb.appDatabase));
    recurrenceRepository = RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
    engine = ReminderEngine(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      recurrenceRepository: recurrenceRepository,
    );
  });

  tearDown(() => testDb.tearDown());

  group('scheduleReminder / cancelReminder / rescheduleReminder', () {
    test('schedules a new, enabled reminder for a task', () async {
      final task = await taskRepository.createTask(title: 'Pay rent');

      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      expect(reminder.id, isNotNull);
      expect(reminder.taskId, task.id);
      expect(reminder.reminderTime, DateTime(2026, 9, 15, 9, 0));
      expect(reminder.isEnabled, isTrue);
    });

    test('cancelReminder disables an existing reminder without deleting it', () async {
      final task = await taskRepository.createTask(title: 'Pay rent');
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );

      await engine.cancelReminder(reminder.id!);

      final fetched = await reminderRepository.getReminder(reminder.id!);
      expect(fetched, isNotNull);
      expect(fetched?.isEnabled, isFalse);
    });

    test('cancelReminder does nothing for a reminder that no longer exists', () async {
      await engine.cancelReminder(999999);
      // No exception, no side effect to check - just proves it doesn't throw.
    });

    test('rescheduleReminder moves the time, re-enables, and clears any snooze', () async {
      final task = await taskRepository.createTask(title: 'Pay rent');
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 9, 15, 9, 0),
      );
      await engine.cancelReminder(reminder.id!);
      await engine.handleSnoozedReminder(
        reminder.id!,
        snoozeMinutes: 10,
        now: DateTime(2026, 9, 15, 9, 0),
      );

      await engine.rescheduleReminder(reminder.id!, DateTime(2026, 9, 16, 9, 0));

      final fetched = await reminderRepository.getReminder(reminder.id!);
      expect(fetched?.reminderTime, DateTime(2026, 9, 16, 9, 0));
      expect(fetched?.isEnabled, isTrue);
      expect(fetched?.snoozeMinutes, isNull);
      expect(fetched?.snoozedUntil, isNull);
    });
  });

  group('getNextOccurrence', () {
    test('delegates to RecurrenceCalculator for a stored rule', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );

      final next = await engine.getNextOccurrence(
        recurrenceRuleId: rule.id!,
        after: DateTime(2026, 1, 1, 8, 0),
      );

      expect(next, DateTime(2026, 1, 2, 8, 0));
    });

    test('returns null when the recurrence rule no longer exists', () async {
      final next = await engine.getNextOccurrence(
        recurrenceRuleId: 999999,
        after: DateTime(2026, 1, 1),
      );
      expect(next, isNull);
    });
  });

  group('handleCompletedRecurringTask', () {
    test('rolls a recurring task forward to its next occurrence, and shifts its reminders', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 9, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 9, 0),
      );
      // A reminder set 30 minutes before the due date.
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 30),
      );
      await taskRepository.completeTask(task.id!);

      final rolled = await engine.handleCompletedRecurringTask(
        task.id!,
        now: DateTime(2026, 1, 1, 9, 5),
      );

      expect(rolled, isNotNull);
      expect(rolled!.dueDate, DateTime(2026, 1, 2, 9, 0));
      expect(rolled.status, TaskStatus.pending);
      expect(rolled.completedAt, isNull);

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.dueDate, DateTime(2026, 1, 2, 9, 0));
      expect(persistedTask?.status, TaskStatus.pending);

      // The reminder must have shifted forward by the same one-day gap,
      // keeping its original 30-minutes-before-due-date offset.
      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 2, 8, 30));
    });

    test('clears any active snooze on the shifted reminders', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 9, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 9, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 9, 0),
      );
      await engine.handleSnoozedReminder(
        reminder.id!,
        snoozeMinutes: 15,
        now: DateTime(2026, 1, 1, 9, 0),
      );
      await taskRepository.completeTask(task.id!);

      await engine.handleCompletedRecurringTask(task.id!, now: DateTime(2026, 1, 1, 9, 5));

      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.snoozeMinutes, isNull);
      expect(persistedReminder?.snoozedUntil, isNull);
      expect(persistedReminder?.isEnabled, isTrue);
    });

    test('leaves the task completed for good once the recurrence has ended', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 9, 0),
        occurrencesCount: 1, // the due date itself is the only occurrence
      );
      final task = await taskRepository.createTask(
        title: 'One-off under the hood',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 9, 0),
      );
      await taskRepository.completeTask(task.id!);

      final rolled = await engine.handleCompletedRecurringTask(
        task.id!,
        now: DateTime(2026, 1, 1, 9, 5),
      );

      expect(rolled, isNull);
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.status, TaskStatus.completed);
      expect(persistedTask?.completedAt, isNotNull);
    });

    test('returns null for a task that is not recurring', () async {
      final task = await taskRepository.createTask(
        title: 'Just a one-time task',
        dueDate: DateTime(2026, 1, 1, 9, 0),
      );
      await taskRepository.completeTask(task.id!);

      final rolled = await engine.handleCompletedRecurringTask(task.id!);
      expect(rolled, isNull);
    });

    test('returns null for a task id that does not exist', () async {
      final rolled = await engine.handleCompletedRecurringTask(999999);
      expect(rolled, isNull);
    });
  });

  group('catchUpMissedOccurrence', () {
    test('jumps a recurring reminder straight to the next future occurrence '
        'after several missed days, without stepping through each one', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      // The app (or device) was inactive from Jan 1st through Jan 6th -
      // five daily occurrences were missed entirely.
      final caughtUp = await engine.catchUpMissedOccurrence(
        reminder.id!,
        now: DateTime(2026, 1, 6, 12, 0),
      );

      expect(caughtUp, isNotNull);
      // The next occurrence strictly after "now" - not Jan 2nd, Jan 3rd,
      // etc. one at a time, straight to Jan 7th.
      expect(caughtUp!.reminderTime, DateTime(2026, 1, 7, 8, 0));

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.dueDate, DateTime(2026, 1, 7, 8, 0));

      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 7, 8, 0));
      expect(persistedReminder?.isEnabled, isTrue);

      // Same rows advanced in place - no duplicate task or reminder was
      // created for any of the missed occurrences.
      expect(await taskRepository.getTask(task.id!), isNotNull);
      expect((await reminderRepository.getRemindersForTask(task.id!)).length, 1);
    });

    test('clears an expired snooze as part of catching up', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );
      await engine.handleSnoozedReminder(
        reminder.id!,
        snoozeMinutes: 10,
        now: DateTime(2026, 1, 1, 8, 0),
      );

      final caughtUp = await engine.catchUpMissedOccurrence(
        reminder.id!,
        now: DateTime(2026, 1, 3, 0, 0),
      );

      expect(caughtUp, isNotNull);
      expect(caughtUp!.snoozeMinutes, isNull);
      expect(caughtUp.snoozedUntil, isNull);
    });

    test('the recurrence rule itself is never lost while catching up', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      await engine.catchUpMissedOccurrence(reminder.id!, now: DateTime(2026, 1, 6, 12, 0));

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.recurrenceRuleId, rule.id);
      expect(await recurrenceRepository.getRule(rule.id!), isNotNull);
    });

    test('disables the reminder once the recurrence ended during the missed time', () async {
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
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      // "Now" is already past the recurrence's own end date.
      final caughtUp = await engine.catchUpMissedOccurrence(
        reminder.id!,
        now: DateTime(2026, 1, 10, 0, 0),
      );

      expect(caughtUp, isNull);
      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.isEnabled, isFalse);
    });

    test('does nothing for a reminder on a non-recurring task', () async {
      final task = await taskRepository.createTask(
        title: 'Just a one-time task',
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      final caughtUp = await engine.catchUpMissedOccurrence(
        reminder.id!,
        now: DateTime(2026, 1, 6, 12, 0),
      );

      expect(caughtUp, isNull);
      final persistedReminder = await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 1, 8, 0));
      expect(persistedReminder?.isEnabled, isTrue);
    });

    test('returns null for a reminder that does not exist', () async {
      final caughtUp = await engine.catchUpMissedOccurrence(999999, now: DateTime(2026, 1, 6));
      expect(caughtUp, isNull);
    });
  });

  group('handleSnoozedReminder', () {
    test('sets snoozedUntil relative to the given now, and persists it', () async {
      final task = await taskRepository.createTask(title: 'Stretch');
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 9, 0),
      );

      final snoozed = await engine.handleSnoozedReminder(
        reminder.id!,
        snoozeMinutes: 10,
        now: DateTime(2026, 1, 1, 9, 0),
      );

      expect(snoozed, isNotNull);
      expect(snoozed!.snoozeMinutes, 10);
      expect(snoozed.snoozedUntil, DateTime(2026, 1, 1, 9, 10));

      final persisted = await reminderRepository.getReminder(reminder.id!);
      expect(persisted?.snoozeMinutes, 10);
      expect(persisted?.snoozedUntil, DateTime(2026, 1, 1, 9, 10));
    });

    test('returns null for a reminder that does not exist', () async {
      final snoozed = await engine.handleSnoozedReminder(999999, snoozeMinutes: 5);
      expect(snoozed, isNull);
    });
  });
}
