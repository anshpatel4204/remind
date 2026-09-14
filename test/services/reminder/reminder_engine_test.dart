import 'package:flutter_test/flutter_test.dart';

import 'package:remind/data/datasources/occurrence_exception_data_source.dart';
import 'package:remind/data/datasources/recurrence_rule_data_source.dart';
import 'package:remind/data/datasources/reminder_data_source.dart';
import 'package:remind/data/datasources/task_data_source.dart';
import 'package:remind/data/datasources/task_tag_data_source.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/repositories/occurrence_exception_repository.dart';
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
  late OccurrenceExceptionRepository occurrenceExceptionRepository;
  late ReminderEngine engine;

  setUp(() {
    testDb = TestAppDatabase.create();
    taskRepository = TaskRepository(
      TaskDataSource(testDb.appDatabase),
      TaskTagDataSource(testDb.appDatabase),
    );
    reminderRepository =
        ReminderRepository(ReminderDataSource(testDb.appDatabase));
    recurrenceRepository =
        RecurrenceRepository(RecurrenceRuleDataSource(testDb.appDatabase));
    occurrenceExceptionRepository = OccurrenceExceptionRepository(
        OccurrenceExceptionDataSource(testDb.appDatabase));
    engine = ReminderEngine(
      taskRepository: taskRepository,
      reminderRepository: reminderRepository,
      recurrenceRepository: recurrenceRepository,
      occurrenceExceptionRepository: occurrenceExceptionRepository,
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

    test('cancelReminder disables an existing reminder without deleting it',
        () async {
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

    test('cancelReminder does nothing for a reminder that no longer exists',
        () async {
      await engine.cancelReminder(999999);
      // No exception, no side effect to check - just proves it doesn't throw.
    });

    test('rescheduleReminder moves the time, re-enables, and clears any snooze',
        () async {
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

      await engine.rescheduleReminder(
          reminder.id!, DateTime(2026, 9, 16, 9, 0));

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
    test(
        'rolls a recurring task forward to its next occurrence, and shifts its reminders',
        () async {
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
      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
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

      await engine.handleCompletedRecurringTask(task.id!,
          now: DateTime(2026, 1, 1, 9, 5));

      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.snoozeMinutes, isNull);
      expect(persistedReminder?.snoozedUntil, isNull);
      expect(persistedReminder?.isEnabled, isTrue);
    });

    test('leaves the task completed for good once the recurrence has ended',
        () async {
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
    test(
        'jumps a recurring reminder straight to the next future occurrence '
        'after several missed days, without stepping through each one',
        () async {
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

      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 7, 8, 0));
      expect(persistedReminder?.isEnabled, isTrue);

      // Same rows advanced in place - no duplicate task or reminder was
      // created for any of the missed occurrences.
      expect(await taskRepository.getTask(task.id!), isNotNull);
      expect(
          (await reminderRepository.getRemindersForTask(task.id!)).length, 1);
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

    test('the recurrence rule itself is never lost while catching up',
        () async {
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

      await engine.catchUpMissedOccurrence(reminder.id!,
          now: DateTime(2026, 1, 6, 12, 0));

      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask?.recurrenceRuleId, rule.id);
      expect(await recurrenceRepository.getRule(rule.id!), isNotNull);
    });

    test(
        'disables the reminder once the recurrence ended during the missed time',
        () async {
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
      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
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
      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 1, 8, 0));
      expect(persistedReminder?.isEnabled, isTrue);
    });

    test('returns null for a reminder that does not exist', () async {
      final caughtUp = await engine.catchUpMissedOccurrence(999999,
          now: DateTime(2026, 1, 6));
      expect(caughtUp, isNull);
    });
  });

  group('skipCurrentOccurrence', () {
    test(
        'rolls the task forward to the occurrence after the skipped one, '
        'without marking it completed', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      final skipped = await engine.skipCurrentOccurrence(
        task.id!,
        now: DateTime(2026, 1, 1, 8, 5),
      );

      expect(skipped, isNotNull);
      expect(skipped!.dueDate, DateTime(2026, 1, 2, 8, 0));
      // Skipping is not completing - status/completedAt are untouched.
      expect(skipped.status, TaskStatus.pending);
      expect(skipped.completedAt, isNull);

      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 2, 8, 0));
    });

    test('records a skipped occurrence exception for the skipped date',
        () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      await engine.skipCurrentOccurrence(task.id!,
          now: DateTime(2026, 1, 1, 8, 5));

      final exception = await occurrenceExceptionRepository.getForOccurrence(
        rule.id!,
        DateTime(2026, 1, 1, 8, 0),
      );
      expect(exception, isNotNull);
      expect(exception?.status, OccurrenceExceptionStatus.skipped);
    });

    test(
        'skipping today does not affect tomorrow\'s occurrence - the '
        "recurrence rule and its future schedule are untouched", () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      await engine.skipCurrentOccurrence(task.id!,
          now: DateTime(2026, 1, 1, 8, 5));

      // The rule itself is unchanged - tomorrow (now the current
      // occurrence) still leads to the day after normally.
      final persistedTask = await taskRepository.getTask(task.id!);
      final next = await engine.getNextOccurrence(
        recurrenceRuleId: rule.id!,
        after: persistedTask!.dueDate!,
      );
      expect(next, DateTime(2026, 1, 3, 8, 0));
      expect((await recurrenceRepository.getRule(rule.id!))?.endDate, isNull);
    });

    test(
        'skipping a rescheduled occurrence advances from its original '
        'anchor, not the rescheduled time', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      // Move just today's occurrence to 2pm.
      await engine.rescheduleCurrentOccurrence(
        task.id!,
        DateTime(2026, 1, 1, 14, 0),
        now: DateTime(2026, 1, 1, 8, 0),
      );

      final skipped = await engine.skipCurrentOccurrence(
        task.id!,
        now: DateTime(2026, 1, 1, 14, 5),
      );

      // The series continues from Jan 1 (the canonical anchor), landing
      // on Jan 2 at the rule's original 8:00 time - not Jan 2 at 2pm.
      expect(skipped?.dueDate, DateTime(2026, 1, 2, 8, 0));
    });

    test('returns null once the recurrence has no occurrence left to roll to',
        () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
        occurrencesCount: 1,
      );
      final task = await taskRepository.createTask(
        title: 'One-off under the hood',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      final skipped = await engine.skipCurrentOccurrence(task.id!,
          now: DateTime(2026, 1, 1, 8, 5));

      expect(skipped, isNull);
    });

    test('returns null for a task that is not recurring', () async {
      final task = await taskRepository.createTask(
        title: 'Just a one-time task',
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      final skipped = await engine.skipCurrentOccurrence(task.id!);
      expect(skipped, isNull);
    });
  });

  group('rescheduleCurrentOccurrence', () {
    test('moves only the current occurrence, leaving the rule untouched',
        () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      final reminder = await engine.scheduleReminder(
        taskId: task.id!,
        reminderTime: DateTime(2026, 1, 1, 8, 0),
      );

      final rescheduled = await engine.rescheduleCurrentOccurrence(
        task.id!,
        DateTime(2026, 1, 1, 14, 0),
        now: DateTime(2026, 1, 1, 8, 0),
      );

      expect(rescheduled, isNotNull);
      expect(rescheduled!.dueDate, DateTime(2026, 1, 1, 14, 0));
      expect(rescheduled.occurrenceOriginalDate, DateTime(2026, 1, 1, 8, 0));

      final persistedReminder =
          await reminderRepository.getReminder(reminder.id!);
      expect(persistedReminder?.reminderTime, DateTime(2026, 1, 1, 14, 0));

      // The recurrence rule's own definition is completely unchanged.
      final persistedRule = await recurrenceRepository.getRule(rule.id!);
      expect(persistedRule?.startDate, DateTime(2026, 1, 1, 8, 0));
    });

    test('records a rescheduled occurrence exception', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      await engine.rescheduleCurrentOccurrence(
        task.id!,
        DateTime(2026, 1, 1, 14, 0),
        now: DateTime(2026, 1, 1, 8, 0),
      );

      final exception = await occurrenceExceptionRepository.getForOccurrence(
        rule.id!,
        DateTime(2026, 1, 1, 8, 0),
      );
      expect(exception?.status, OccurrenceExceptionStatus.rescheduled);
      expect(exception?.rescheduledTo, DateTime(2026, 1, 1, 14, 0));
    });

    test(
        'completing a rescheduled occurrence advances the series from its '
        'original anchor, not the rescheduled time', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Drink water',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );
      await engine.rescheduleCurrentOccurrence(
        task.id!,
        DateTime(2026, 1, 1, 14, 0),
        now: DateTime(2026, 1, 1, 8, 0),
      );
      await taskRepository.completeTask(task.id!);

      final rolled = await engine.handleCompletedRecurringTask(
        task.id!,
        now: DateTime(2026, 1, 1, 14, 5),
      );

      // Next occurrence is Jan 2 at the rule's original 8:00 time, not
      // Jan 2 at 2pm (which a naive "anchor on dueDate" implementation
      // would have produced).
      expect(rolled?.dueDate, DateTime(2026, 1, 2, 8, 0));
      // The one-off reschedule bookkeeping is cleared once the series
      // has moved on to a fresh occurrence.
      expect(rolled?.occurrenceOriginalDate, isNull);
    });

    test('returns null for a task that is not recurring', () async {
      final task = await taskRepository.createTask(
        title: 'Just a one-time task',
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      final rescheduled = await engine.rescheduleCurrentOccurrence(
        task.id!,
        DateTime(2026, 1, 2, 8, 0),
      );
      expect(rescheduled, isNull);
    });
  });

  group('cancelFutureOccurrences', () {
    test(
        'stops the series after the current occurrence while preserving '
        'the task and its current due date', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 5, 8, 0),
      );

      final result = await engine.cancelFutureOccurrences(
        task.id!,
        now: DateTime(2026, 1, 5, 8, 5),
      );

      expect(result, isNotNull);
      // The task itself (its history, its current due date) is preserved
      // - this is not the same as deleting the task or its rule.
      final persistedTask = await taskRepository.getTask(task.id!);
      expect(persistedTask, isNotNull);
      expect(persistedTask?.dueDate, DateTime(2026, 1, 5, 8, 0));
      expect(persistedTask?.recurrenceRuleId, rule.id);

      // The rule itself still exists, now bounded to end at the current
      // occurrence.
      final persistedRule = await recurrenceRepository.getRule(rule.id!);
      expect(persistedRule, isNotNull);
      expect(persistedRule?.endDate, DateTime(2026, 1, 5, 8, 0));
    });

    test('the current occurrence remains valid and completable', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 5, 8, 0),
      );

      await engine.cancelFutureOccurrences(task.id!,
          now: DateTime(2026, 1, 5, 8, 5));

      // The occurrence exactly at the new endDate still qualifies.
      final firstOccurrence = await engine.getNextOccurrence(
        recurrenceRuleId: rule.id!,
        after: DateTime(2026, 1, 5, 7, 59),
      );
      expect(firstOccurrence, DateTime(2026, 1, 5, 8, 0));

      // But nothing after it does.
      final next = await engine.getNextOccurrence(
        recurrenceRuleId: rule.id!,
        after: DateTime(2026, 1, 5, 8, 0),
      );
      expect(next, isNull);
    });

    test(
        'cancelling from the very first occurrence does not throw (endDate '
        'never ends up before startDate)', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      await engine.cancelFutureOccurrences(task.id!,
          now: DateTime(2026, 1, 1, 8, 5));

      final persistedRule = await recurrenceRepository.getRule(rule.id!);
      expect(persistedRule?.endDate, DateTime(2026, 1, 1, 8, 0));
      expect(persistedRule?.startDate, DateTime(2026, 1, 1, 8, 0));
    });

    test('records a cancelled occurrence exception', () async {
      final rule = await recurrenceRepository.createRule(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026, 1, 1, 8, 0),
      );
      final task = await taskRepository.createTask(
        title: 'Take medicine',
        recurrenceRuleId: rule.id,
        dueDate: DateTime(2026, 1, 5, 8, 0),
      );

      await engine.cancelFutureOccurrences(task.id!,
          now: DateTime(2026, 1, 5, 8, 5));

      final exception = await occurrenceExceptionRepository.getForOccurrence(
        rule.id!,
        DateTime(2026, 1, 5, 8, 0),
      );
      expect(exception?.status, OccurrenceExceptionStatus.cancelled);
    });

    test('returns null for a task that is not recurring', () async {
      final task = await taskRepository.createTask(
        title: 'Just a one-time task',
        dueDate: DateTime(2026, 1, 1, 8, 0),
      );

      final result = await engine.cancelFutureOccurrences(task.id!);
      expect(result, isNull);
    });
  });

  group('handleSnoozedReminder', () {
    test('sets snoozedUntil relative to the given now, and persists it',
        () async {
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
      final snoozed =
          await engine.handleSnoozedReminder(999999, snoozeMinutes: 5);
      expect(snoozed, isNull);
    });
  });
}
