import '../../core/utils/recurrence_calculator.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder_model.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/recurrence_repository.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../data/repositories/task_repository.dart';

/// Owns every piece of reminder-scheduling *logic*: when a reminder should
/// next fire, what happens when a recurring task is completed, and what
/// happens when a reminder is snoozed. Screens and widgets never implement
/// any of this themselves - they call into this service, which is the only
/// place that talks to [RecurrenceCalculator] and coordinates
/// [TaskRepository], [ReminderRepository] and [RecurrenceRepository]
/// together.
///
/// This part deliberately stops at *scheduling logic*. It does not touch
/// `flutter_local_notifications` or any platform notification API, and it
/// never calls `DateTime.now()` internally for anything that affects a
/// stored result - every method that needs "the current moment" accepts it
/// as an optional [now] parameter (defaulting to `DateTime.now()` only at
/// the call site), so every code path stays fully testable with a fixed,
/// caller-chosen clock.
class ReminderEngine {
  ReminderEngine({
    required TaskRepository taskRepository,
    required ReminderRepository reminderRepository,
    required RecurrenceRepository recurrenceRepository,
  })  : _taskRepository = taskRepository,
        _reminderRepository = reminderRepository,
        _recurrenceRepository = recurrenceRepository;

  final TaskRepository _taskRepository;
  final ReminderRepository _reminderRepository;
  final RecurrenceRepository _recurrenceRepository;

  /// Schedules a new reminder for [taskId], firing at [reminderTime].
  ///
  /// This only records the reminder's row (time, type, enabled) - it does
  /// not touch any OS notification, since that integration is a later
  /// part of this project. [reminderTime] is taken as given rather than
  /// derived here, since a caller may want a reminder at, before, or
  /// entirely independent of the task's due date.
  Future<ReminderModel> scheduleReminder({
    required int taskId,
    required DateTime reminderTime,
    ReminderType reminderType = ReminderType.notification,
  }) {
    return _reminderRepository.createReminder(
      taskId: taskId,
      reminderTime: reminderTime,
      reminderType: reminderType,
    );
  }

  /// Cancels [reminderId] by disabling it. The row itself is kept (rather
  /// than deleted) so its history isn't lost and it can be re-enabled by
  /// [rescheduleReminder] later; a caller that truly wants it gone can
  /// still delete it directly via [ReminderRepository.deleteReminder].
  /// Does nothing if the reminder no longer exists.
  Future<void> cancelReminder(int reminderId) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return;
    await _reminderRepository.updateReminder(reminder.copyWith(isEnabled: false));
  }

  /// Moves [reminderId] to fire at [newReminderTime] instead, re-enabling
  /// it if it had been cancelled, and clearing any active snooze - a
  /// snooze computed relative to the old time no longer means anything
  /// once the reminder's own time has moved. Does nothing if the reminder
  /// no longer exists.
  Future<void> rescheduleReminder(int reminderId, DateTime newReminderTime) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return;
    await _reminderRepository.updateReminder(
      reminder.copyWith(reminderTime: newReminderTime, isEnabled: true, clearSnooze: true),
    );
  }

  /// The next occurrence of the recurrence rule identified by
  /// [recurrenceRuleId], strictly after [after] (or at-or-after, when
  /// [inclusive] is true). A pure pass-through to
  /// [RecurrenceCalculator.nextOccurrence] once the rule itself has been
  /// loaded; returns null if no such rule exists, or if the recurrence has
  /// already ended by that point.
  Future<DateTime?> getNextOccurrence({
    required int recurrenceRuleId,
    required DateTime after,
    bool inclusive = false,
  }) async {
    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;
    return RecurrenceCalculator.nextOccurrence(rule, after: after, inclusive: inclusive);
  }

  /// Call this when a recurring task (one with a `recurrenceRuleId` and a
  /// due date) has just been marked complete.
  ///
  /// If its recurrence rule has another occurrence remaining after the
  /// just-completed due date, the *same* task row is rolled forward to
  /// it: due date advances to that next occurrence, status returns to
  /// pending, and `completedAt` is cleared - REmind models a recurring
  /// task as one persistent row that keeps advancing, not a new row
  /// created per occurrence. Every one of the task's existing reminders
  /// is shifted forward by exactly the same real-elapsed gap between the
  /// old and new due dates (so a reminder that was, say, 30 minutes
  /// before the due date stays 30 minutes before the new one) and has any
  /// snooze on it cleared, since a snooze from the finished occurrence has
  /// no bearing on the next one.
  ///
  /// If the recurrence has ended (its end date or occurrence count has
  /// been reached), nothing is rolled forward: the task is left completed
  /// for good, and this returns null. Returns null too if [taskId] does
  /// not exist, is not actually recurring, or has no due date to advance
  /// from.
  Future<TaskModel?> handleCompletedRecurringTask(int taskId, {DateTime? now}) async {
    final task = await _taskRepository.getTask(taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    final oldDueDate = task.dueDate;
    if (recurrenceRuleId == null || oldDueDate == null) return null;

    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;

    final next = RecurrenceCalculator.nextOccurrence(rule, after: oldDueDate);
    if (next == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final shift = next.difference(oldDueDate);

    final updatedTask = task.copyWith(
      dueDate: next,
      status: TaskStatus.pending,
      clearCompletedAt: true,
      updatedAt: effectiveNow,
    );
    await _taskRepository.updateTask(updatedTask);

    final reminders = await _reminderRepository.getRemindersForTask(taskId);
    for (final reminder in reminders) {
      await _reminderRepository.updateReminder(
        reminder.copyWith(
          reminderTime: reminder.reminderTime.add(shift),
          isEnabled: true,
          clearSnooze: true,
        ),
      );
    }

    return updatedTask;
  }

  /// Called at startup (or wherever a reminder's stored fire time may
  /// have already passed without ever being handled - the app was
  /// closed, or the device was off, through one or more of the task's
  /// own recurrence occurrences) for the reminder identified by
  /// [reminderId].
  ///
  /// For a reminder attached to a recurring task, this rolls the task's
  /// due date forward - and every one of its reminders by that same
  /// elapsed shift, exactly like [handleCompletedRecurringTask] - to the
  /// first occurrence that is still strictly after [now]. This is a
  /// single jump directly to the next valid occurrence, never a step
  /// through each missed one in between: a task whose daily 8am reminder
  /// was missed for a week produces one catch-up jump to today, not
  /// seven queued reminders (and never a duplicate row for any
  /// occurrence in between - the same task/reminder rows just advance).
  ///
  /// If the recurrence has already ended before reaching a future
  /// occurrence, there is nothing left to schedule: the reminder is
  /// disabled (rather than left enabled with a stale past time forever)
  /// and this returns null.
  ///
  /// For a reminder whose task is not recurring (or has no due date),
  /// there is no schedule to catch up to - it is simply an overdue
  /// one-off reminder - so this does nothing and returns null.
  Future<ReminderModel?> catchUpMissedOccurrence(int reminderId, {DateTime? now}) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return null;

    final task = await _taskRepository.getTask(reminder.taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    final oldDueDate = task.dueDate;
    if (recurrenceRuleId == null || oldDueDate == null) return null;

    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final next = RecurrenceCalculator.nextOccurrence(rule, after: effectiveNow);
    if (next == null) {
      // The recurrence ended somewhere during the missed time - nothing
      // left to catch up to; stop scheduling it for good.
      await _reminderRepository.updateReminder(reminder.copyWith(isEnabled: false));
      return null;
    }

    final shift = next.difference(oldDueDate);
    final updatedTask = task.copyWith(dueDate: next, updatedAt: effectiveNow);
    await _taskRepository.updateTask(updatedTask);

    final reminders = await _reminderRepository.getRemindersForTask(task.id!);
    ReminderModel? caughtUpTarget;
    for (final taskReminder in reminders) {
      final updated = taskReminder.copyWith(
        reminderTime: taskReminder.reminderTime.add(shift),
        isEnabled: true,
        clearSnooze: true,
      );
      await _reminderRepository.updateReminder(updated);
      if (taskReminder.id == reminderId) caughtUpTarget = updated;
    }
    return caughtUpTarget;
  }

  /// Snoozes [reminderId] for [snoozeMinutes] minutes starting from [now]
  /// (defaulting to the current device time). Returns the updated
  /// reminder, or null if it no longer exists.
  ///
  /// This intentionally does not call [ReminderRepository.snoozeReminder]:
  /// that method always uses `DateTime.now()` internally, which would
  /// make this untestable with a fixed clock. Every scheduling decision
  /// in this engine goes through an injectable [now] instead.
  Future<ReminderModel?> handleSnoozedReminder(
    int reminderId, {
    required int snoozeMinutes,
    DateTime? now,
  }) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final updated = reminder.copyWith(
      snoozeMinutes: snoozeMinutes,
      snoozedUntil: effectiveNow.add(Duration(minutes: snoozeMinutes)),
    );
    await _reminderRepository.updateReminder(updated);
    return updated;
  }
}
