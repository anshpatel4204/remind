import 'package:flutter/material.dart';

import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../screens/task_form_screen.dart';

/// Shared "this recurring task is about to be edited/deleted" flows, used
/// by every screen that lists tasks (Home, Tasks, Calendar, Task Details)
/// so a recurring task is handled identically - and safely - everywhere,
/// per the spec's "editing/skipping/rescheduling one occurrence must NOT
/// accidentally modify or delete the entire recurring series" requirement.
/// A non-recurring task never sees any of this extra UI: both entry
/// points below check `task.recurrenceRuleId` first and fall straight
/// through to the plain, single-task behavior when it's null.

/// Opens the Add/Edit Task form for [task], first asking a recurring
/// task's user which occurrences the edit should apply to.
///
/// "This occurrence only" opens a lightweight date/time-only reschedule
/// dialog instead of the full form - this pass's deliberate, documented
/// scope for "edit a single occurrence" (see the Part 12.5 final report:
/// full per-occurrence field overrides, e.g. a different title just for
/// one date, are a possible future enhancement, not built here). "This
/// and future occurrences" and "Entire series" both open the normal form
/// and, under the hood, apply the same series-level update - see the
/// final report for why REmind's single-row-per-series architecture (no
/// per-occurrence rows ever created) makes those two options equivalent
/// in practice; both are still offered because that is the picker a
/// Google Calendar/Outlook user already expects to see.
///
/// Returns true if anything was actually changed, so the caller knows to
/// reload its task list; false if the user backed out at any step.
Future<bool> openRecurringAwareEdit(
    BuildContext context, TaskModel task) async {
  if (task.recurrenceRuleId == null) {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: task)),
    );
    return result ?? false;
  }

  final scope = await _pickApplyScope(context);
  if (scope == null) return false;

  if (scope == _EditScope.occurrenceOnly) {
    if (!context.mounted) return false;
    return _rescheduleOccurrenceOnly(context, task);
  }

  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: task)),
  );
  return result ?? false;
}

/// Deletes [task], first asking a recurring task's user whether they mean
/// just its current occurrence or the whole series - the plain
/// non-recurring confirmation dialog is used unchanged when it isn't
/// recurring. Returns true if anything was deleted.
Future<bool> confirmAndDeleteTask(BuildContext context, TaskModel task) async {
  final repos = RepositoryScope.of(context);

  if (task.recurrenceRuleId == null) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
            '"${task.title}" will be permanently deleted, along with its reminder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!context.mounted) return false;
    await repos.notificationScheduler.cancelNotificationsForTask(task.id!);
    await repos.taskRepository.deleteTask(task.id!);
    return true;
  }

  final scope = await showDialog<_DeleteScope>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete recurring task'),
      content: Text(
        '"${task.title}" repeats. Delete just this occurrence, or the '
        'entire recurring series?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_DeleteScope.occurrenceOnly),
          child: const Text('This occurrence'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_DeleteScope.entireSeries),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: const Text('Entire series'),
        ),
      ],
    ),
  );
  if (scope == null) return false;
  if (!context.mounted) return false;

  if (scope == _DeleteScope.occurrenceOnly) {
    // "Skip this occurrence" is the same operation as "Delete this
    // occurrence": it removes just the current dated occurrence and
    // rolls the same task row forward to whichever occurrence comes
    // after it - see ReminderEngine.skipCurrentOccurrence.
    await repos.notificationScheduler.skipOccurrence(task.id!);
  } else {
    await repos.notificationScheduler.cancelNotificationsForTask(task.id!);
    await repos.taskRepository.deleteTask(task.id!);
  }
  return true;
}

enum _EditScope { occurrenceOnly, seriesOrFuture }

enum _DeleteScope { occurrenceOnly, entireSeries }

Future<_EditScope?> _pickApplyScope(BuildContext context) {
  return showDialog<_EditScope>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Apply changes to'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EditScope.occurrenceOnly),
          child: const Text('This occurrence only'),
        ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EditScope.seriesOrFuture),
          child: const Text('This and future occurrences'),
        ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EditScope.seriesOrFuture),
          child: const Text('Entire series'),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      ],
    ),
  );
}

Future<bool> _rescheduleOccurrenceOnly(
    BuildContext context, TaskModel task) async {
  final initialDate = task.dueDate ?? DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return false;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initialDate.hour, minute: initialDate.minute),
  );
  if (time == null || !context.mounted) return false;

  final newDateTime =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  await RepositoryScope.of(context)
      .notificationScheduler
      .rescheduleOccurrence(task.id!, newDateTime);
  return true;
}
