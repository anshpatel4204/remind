import '../../data/models/enums.dart';
import '../../data/models/task_model.dart';

/// The status actually shown to the user for a task, as opposed to the
/// smaller set of statuses actually stored in the database (see
/// [TaskStatus]).
enum TaskDisplayStatus {
  pending,
  inProgress,
  completed,
  overdue,
  snoozed,
  cancelled
}

/// Derives the [TaskDisplayStatus] a task should show, from its stored
/// [TaskModel] plus the current moment.
///
/// `Overdue` and `Snoozed` are deliberately *not* values a user can pick
/// directly (see the task edit form, which only offers Pending/In
/// Progress/Completed/Cancelled) - they are always computed here, from the
/// due date and reminder state, so they can never go stale or contradict
/// the task's actual due date the way a manually-set "Overdue" flag could
/// after an edit.
class TaskStatusCalculator {
  const TaskStatusCalculator._();

  /// [now] should be the current device local time. [hasActiveSnooze]
  /// should be true when the task has at least one enabled reminder whose
  /// snooze is still in effect (`snoozedUntil` in the future).
  static TaskDisplayStatus displayStatusFor(
    TaskModel task, {
    required DateTime now,
    bool hasActiveSnooze = false,
  }) {
    // Completed and Cancelled are terminal: the stored status always wins,
    // regardless of due date or snooze state.
    if (task.status == TaskStatus.completed) return TaskDisplayStatus.completed;
    if (task.status == TaskStatus.cancelled) return TaskDisplayStatus.cancelled;

    // An active snooze means the user has already acknowledged the task
    // and deferred it, so it is shown as Snoozed rather than Overdue.
    if (hasActiveSnooze) return TaskDisplayStatus.snoozed;

    final dueDate = task.dueDate;
    if (dueDate != null && dueDate.isBefore(now)) {
      return TaskDisplayStatus.overdue;
    }

    return task.status == TaskStatus.inProgress
        ? TaskDisplayStatus.inProgress
        : TaskDisplayStatus.pending;
  }
}
