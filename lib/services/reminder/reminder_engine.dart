import '../../core/utils/recurrence_calculator.dart';
import '../../data/models/enums.dart';
import '../../data/models/reminder_model.dart';
import '../../data/models/task_model.dart';
import '../../data/repositories/occurrence_exception_repository.dart';
import '../../data/repositories/recurrence_repository.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../data/repositories/task_repository.dart';

/// Owns every piece of reminder-scheduling *logic*: when a reminder should
/// next fire, what happens when a recurring task is completed, and what
/// happens when a reminder is snoozed - plus, as of Part 12.5, every
/// per-occurrence action a recurring task supports (skip, reschedule, and
/// cancel-future) that must affect exactly one occurrence without ever
/// touching the rest of the series. Screens and widgets never implement
/// any of this themselves - they call into this service, which is the only
/// place that talks to [RecurrenceCalculator] and coordinates
/// [TaskRepository], [ReminderRepository], [RecurrenceRepository] and
/// [OccurrenceExceptionRepository] together.
///
/// This part deliberately stops at *scheduling logic*. It does not touch
/// `flutter_local_notifications` or any platform notification API, and it
/// never calls `DateTime.now()` internally for anything that affects a
/// stored result - every method that needs "the current moment" accepts it
/// as an optional [now] parameter (defaulting to `DateTime.now()` only at
/// the call site), so every code path stays fully testable with a fixed,
/// caller-chosen clock.
///
/// ### How a recurring task's "current occurrence" is represented
///
/// REmind never creates a database row per occurrence. A recurring task
/// is one [TaskModel] row that keeps advancing: [dueDate] is always
/// "whichever occurrence is currently active" (upcoming, due, or
/// overdue), and completing it (or skipping/catching-up past it) rolls
/// that same row forward to the next occurrence - see
/// [handleCompletedRecurringTask].
///
/// A one-off action on a single occurrence - reschedule this occurrence
/// only - moves [TaskModel.dueDate] to the new time but must not let the
/// *rest* of the series drift with it. [TaskModel.occurrenceOriginalDate]
/// is what prevents that: it records the occurrence's canonical,
/// un-rescheduled date/time whenever the two differ, and every method
/// below that computes "the next occurrence" anchors on
/// `occurrenceOriginalDate ?? dueDate` rather than on [dueDate] alone.
/// [OccurrenceExceptionRepository] separately records *that* an action was
/// taken (skip/cancel/reschedule) against a given occurrence date, purely
/// as an append-only history/audit log keyed by the same (rule,
/// occurrence date) identity - it is never itself read back to decide
/// what the next occurrence is; [occurrenceOriginalDate] is.
class ReminderEngine {
  ReminderEngine({
    required TaskRepository taskRepository,
    required ReminderRepository reminderRepository,
    required RecurrenceRepository recurrenceRepository,
    OccurrenceExceptionRepository? occurrenceExceptionRepository,
  })  : _taskRepository = taskRepository,
        _reminderRepository = reminderRepository,
        _recurrenceRepository = recurrenceRepository,
        _occurrenceExceptionRepository = occurrenceExceptionRepository;

  final TaskRepository _taskRepository;
  final ReminderRepository _reminderRepository;
  final RecurrenceRepository _recurrenceRepository;

  /// Nullable only so existing tests that construct a [ReminderEngine]
  /// without an occurrence-exception repository keep compiling; every
  /// production wiring (see `AppRepositories`) always supplies one. Never
  /// null in practice outside of tests that don't exercise the new
  /// occurrence actions.
  final OccurrenceExceptionRepository? _occurrenceExceptionRepository;

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
    await _reminderRepository
        .updateReminder(reminder.copyWith(isEnabled: false));
  }

  /// Moves [reminderId] to fire at [newReminderTime] instead, re-enabling
  /// it if it had been cancelled, and clearing any active snooze - a
  /// snooze computed relative to the old time no longer means anything
  /// once the reminder's own time has moved. Does nothing if the reminder
  /// no longer exists.
  Future<void> rescheduleReminder(
      int reminderId, DateTime newReminderTime) async {
    final reminder = await _reminderRepository.getReminder(reminderId);
    if (reminder == null) return;
    await _reminderRepository.updateReminder(
      reminder.copyWith(
          reminderTime: newReminderTime, isEnabled: true, clearSnooze: true),
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
    return RecurrenceCalculator.nextOccurrence(rule,
        after: after, inclusive: inclusive);
  }

  /// The occurrence date recurrence math should anchor on for [task]: its
  /// canonical, un-rescheduled date/time. Equal to [TaskModel.dueDate]
  /// unless the current occurrence has been individually rescheduled (see
  /// [TaskModel.occurrenceOriginalDate]), in which case it's the date the
  /// occurrence would still be at if that one-off reschedule had never
  /// happened.
  DateTime? _anchorFor(TaskModel task) =>
      task.occurrenceOriginalDate ?? task.dueDate;

  /// Call this when a recurring task (one with a `recurrenceRuleId` and a
  /// due date) has just been marked complete.
  ///
  /// If its recurrence rule has another occurrence remaining after the
  /// just-completed occurrence's canonical date (see [_anchorFor] - this
  /// is deliberately not always the same as the due date just completed,
  /// so completing a rescheduled occurrence can never drift the rest of
  /// the series), the *same* task row is rolled forward to it: due date
  /// advances to that next occurrence, status returns to pending,
  /// `completedAt` is cleared, and any per-occurrence reschedule bookkeeping
  /// is cleared - REmind models a recurring task as one persistent row
  /// that keeps advancing, not a new row created per occurrence. Every one
  /// of the task's existing reminders is shifted forward by exactly the
  /// same real-elapsed gap between the old and new due dates (so a
  /// reminder that was, say, 30 minutes before the due date stays 30
  /// minutes before the new one) and has any snooze on it cleared, since a
  /// snooze from the finished occurrence has no bearing on the next one.
  ///
  /// If the recurrence has ended (its end date or occurrence count has
  /// been reached), nothing is rolled forward: the task is left completed
  /// for good, and this returns null. Returns null too if [taskId] does
  /// not exist, is not actually recurring, or has no due date to advance
  /// from.
  Future<TaskModel?> handleCompletedRecurringTask(int taskId,
      {DateTime? now}) async {
    final task = await _taskRepository.getTask(taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    final oldDueDate = task.dueDate;
    final anchor = _anchorFor(task);
    if (recurrenceRuleId == null || oldDueDate == null || anchor == null) {
      return null;
    }

    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;

    final next = RecurrenceCalculator.nextOccurrence(rule, after: anchor);
    if (next == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final shift = next.difference(oldDueDate);

    final updatedTask = task.copyWith(
      dueDate: next,
      status: TaskStatus.pending,
      clearCompletedAt: true,
      clearOccurrenceOriginalDate: true,
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
  /// Deliberately does not record an occurrence exception for whatever
  /// was silently skipped over - see the class-level docs and this
  /// part's final report for why REmind does not materialize a "Missed"
  /// history entry for every occurrence silently caught up over.
  ///
  /// If the recurrence has already ended before reaching a future
  /// occurrence, there is nothing left to schedule: the reminder is
  /// disabled (rather than left enabled with a stale past time forever)
  /// and this returns null.
  ///
  /// For a reminder whose task is not recurring (or has no due date),
  /// there is no schedule to catch up to - it is simply an overdue
  /// one-off reminder - so this does nothing and returns null.
  Future<ReminderModel?> catchUpMissedOccurrence(int reminderId,
      {DateTime? now}) async {
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
      await _reminderRepository
          .updateReminder(reminder.copyWith(isEnabled: false));
      return null;
    }

    final shift = next.difference(oldDueDate);
    final updatedTask = task.copyWith(
      dueDate: next,
      clearOccurrenceOriginalDate: true,
      updatedAt: effectiveNow,
    );
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
  ///
  /// Snoozing a recurring task's reminder only ever affects the single
  /// currently-active occurrence: nothing here touches the recurrence
  /// rule or computes a next occurrence, so (for example) snoozing today's
  /// "Drink water" reminder by 30 minutes has no effect at all on
  /// tomorrow's normal firing, which only comes into being later, when
  /// today's occurrence is completed/skipped/caught-up (each of which
  /// already clears any snooze on the way - see [handleCompletedRecurringTask]).
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

  /// "Skip this occurrence" (and, equivalently, "Delete this occurrence" -
  /// see the Part 12.5 final report for why these two user-facing actions
  /// share one implementation): removes just the task's *current*
  /// occurrence from the series and rolls the same row forward to the
  /// occurrence after it, without marking anything completed.
  ///
  /// Records an [OccurrenceExceptionRepository.recordSkipped] entry for
  /// the skipped occurrence's canonical date (history/audit only - see
  /// the class docs), then behaves exactly like
  /// [handleCompletedRecurringTask] for the roll-forward/reminder-shift
  /// mechanics, except the task's `status`/`completedAt` are left alone
  /// (skipping is not completing).
  ///
  /// Returns null - and rolls nothing forward - if [taskId] doesn't
  /// exist, isn't recurring, has no due date, or the recurrence has no
  /// occurrence left after the skipped one (in which case the task is
  /// left exactly as it was, still showing its last occurrence, and the
  /// caller decides what to do next, e.g. treat it like the series has
  /// ended).
  Future<TaskModel?> skipCurrentOccurrence(int taskId, {DateTime? now}) async {
    final task = await _taskRepository.getTask(taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    final oldDueDate = task.dueDate;
    final anchor = _anchorFor(task);
    if (recurrenceRuleId == null || oldDueDate == null || anchor == null) {
      return null;
    }

    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final next = RecurrenceCalculator.nextOccurrence(rule, after: anchor);

    await _occurrenceExceptionRepository?.recordSkipped(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: anchor,
      now: effectiveNow,
    );

    if (next == null) return null;

    final shift = next.difference(oldDueDate);
    final updatedTask = task.copyWith(
      dueDate: next,
      clearOccurrenceOriginalDate: true,
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

  /// "Reschedule this occurrence" (and, with this pass's scope decision,
  /// "Edit this occurrence" - see the Part 12.5 final report): moves the
  /// task's *current* occurrence to [newDateTime] without touching the
  /// recurrence pattern or any other occurrence.
  ///
  /// Records the occurrence's canonical date and the new time via
  /// [OccurrenceExceptionRepository.recordRescheduled], moves
  /// [TaskModel.dueDate] to [newDateTime], and - critically - sets
  /// [TaskModel.occurrenceOriginalDate] to the occurrence's canonical
  /// date so that whenever this occurrence is later completed, skipped,
  /// or caught up, the *next* occurrence is computed from the original
  /// schedule rather than from this one-off new time (see the class
  /// docs). Every one of the task's reminders is shifted by the same
  /// delta as the due date, exactly like [handleCompletedRecurringTask].
  ///
  /// Returns null (and changes nothing) if [taskId] doesn't exist, isn't
  /// recurring, or has no due date.
  Future<TaskModel?> rescheduleCurrentOccurrence(
    int taskId,
    DateTime newDateTime, {
    DateTime? now,
  }) async {
    final task = await _taskRepository.getTask(taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    final oldDueDate = task.dueDate;
    final anchor = _anchorFor(task);
    if (recurrenceRuleId == null || oldDueDate == null || anchor == null) {
      return null;
    }

    final effectiveNow = now ?? DateTime.now();

    await _occurrenceExceptionRepository?.recordRescheduled(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: anchor,
      rescheduledTo: newDateTime,
      now: effectiveNow,
    );

    final shift = newDateTime.difference(oldDueDate);
    final updatedTask = task.copyWith(
      dueDate: newDateTime,
      occurrenceOriginalDate: anchor,
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

  /// "Cancel future occurrences" - stops the series from producing any
  /// occurrence after the current one, while leaving the task itself (and
  /// its history: creation date, past completions, its current due
  /// occurrence) fully in place, per the spec's "preserve history"
  /// requirement. This is deliberately *not* the same as deleting the
  /// task or its recurrence rule.
  ///
  /// Implemented by setting the recurrence rule's `endDate` to the
  /// current occurrence's own canonical date - the same `endDate`
  /// mechanism every other "recurrence has ended" check in this engine
  /// and [RecurrenceCalculator] already understands, so nothing else
  /// needs to change to make [handleCompletedRecurringTask] naturally
  /// stop rolling the task forward the next time it's completed. The
  /// current occurrence itself remains valid under this new end date (an
  /// occurrence exactly *at* `endDate` still qualifies - only ones after
  /// it don't) and can still be completed, snoozed, or rescheduled
  /// normally.
  ///
  /// Returns null (and changes nothing) if [taskId] doesn't exist or
  /// isn't recurring.
  Future<TaskModel?> cancelFutureOccurrences(int taskId,
      {DateTime? now}) async {
    final task = await _taskRepository.getTask(taskId);
    if (task == null) return null;

    final recurrenceRuleId = task.recurrenceRuleId;
    if (recurrenceRuleId == null) return null;

    final rule = await _recurrenceRepository.getRule(recurrenceRuleId);
    if (rule == null) return null;

    final effectiveNow = now ?? DateTime.now();
    final anchor = _anchorFor(task) ?? effectiveNow;

    await _occurrenceExceptionRepository?.recordCancelled(
      recurrenceRuleId: recurrenceRuleId,
      occurrenceDate: anchor,
      now: effectiveNow,
    );

    // endDate is set to the anchor occurrence itself (not one tick
    // before it): RecurrenceCalculator's end-date check excludes any
    // occurrence strictly *after* endDate, so this keeps the current
    // occurrence valid while excluding every occurrence after it - and,
    // unlike subtracting a moment from it, can never push endDate before
    // startDate (which would fail RecurrenceRepository's validation) even
    // when the very first occurrence is the one being cancelled from.
    final updatedRule = rule.copyWith(endDate: anchor);
    await _recurrenceRepository.updateRule(updatedRule);

    return task;
  }
}
