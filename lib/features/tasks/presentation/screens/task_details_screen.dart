import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/recurrence_text.dart';
import '../../../../core/utils/task_status_calculator.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/reminder_model.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/recurrence_rule_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../../services/notification/notification_scheduler.dart';
import '../widgets/priority_badge.dart';
import '../widgets/recurring_task_actions.dart';
import '../widgets/status_badge.dart';

/// Full detail view for a single task: every field, its reminder (if any),
/// and the Complete/Edit/Delete/Snooze/Reschedule actions.
class TaskDetailsScreen extends StatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId});

  final int taskId;

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  late Future<_TaskDetailsData?> _future;
  bool _initialized = false;
  bool _busy = false;

  // Loading depends on RepositoryScope.of(context), which cannot be called
  // from initState() - it must wait until didChangeDependencies().
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_TaskDetailsData?> _load() async {
    final repos = RepositoryScope.of(context);
    final task = await repos.taskRepository.getTask(widget.taskId);
    if (task == null) return null;

    final category = task.categoryId == null
        ? null
        : await repos.categoryRepository.getCategory(task.categoryId!);
    final tags = await repos.taskRepository.getTagsForTask(task.id!);
    final reminders =
        await repos.reminderRepository.getRemindersForTask(task.id!);
    final recurrenceRule = task.recurrenceRuleId == null
        ? null
        : await repos.recurrenceRepository.getRule(task.recurrenceRuleId!);

    return _TaskDetailsData(
      task: task,
      category: category,
      tags: tags,
      reminder: reminders.isEmpty ? null : reminders.first,
      recurrenceRule: recurrenceRule,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _complete(TaskModel task) async {
    setState(() => _busy = true);
    // Goes through notificationScheduler (not taskRepository directly) so
    // the task's reminder notification(s) are cancelled - and, for a
    // recurring task, rescheduled for the next occurrence - rather than
    // firing again for a task that's already done.
    await RepositoryScope.of(context)
        .notificationScheduler
        .completeTask(task.id!);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    _showSnack('Task completed');
  }

  Future<void> _reopen(TaskModel task) async {
    setState(() => _busy = true);
    await RepositoryScope.of(context).taskRepository.reopenTask(task.id!);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _edit(TaskModel task) async {
    final changed = await openRecurringAwareEdit(context, task);
    if (!mounted || !changed) return;
    _reload();
  }

  Future<void> _delete(TaskModel task) async {
    final deleted = await confirmAndDeleteTask(context, task);
    if (!mounted || !deleted) return;
    Navigator.of(context).pop();
  }

  /// "Skip this occurrence": removes just the task's current occurrence
  /// and rolls it forward to whichever occurrence comes after it -
  /// nothing else in the series changes. See
  /// ReminderEngine.skipCurrentOccurrence for the mechanics.
  Future<void> _skipOccurrence(TaskModel task) async {
    setState(() => _busy = true);
    await RepositoryScope.of(context)
        .notificationScheduler
        .skipOccurrence(task.id!);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    _showSnack('Occurrence skipped');
  }

  /// "Cancel future occurrences": the current occurrence (shown on this
  /// screen right now) is left completely alone and can still be
  /// completed/snoozed/rescheduled normally - only occurrences after it
  /// stop being generated. See ReminderEngine.cancelFutureOccurrences.
  Future<void> _cancelFutureOccurrences(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel future occurrences?'),
        content: const Text(
          "This occurrence stays exactly as it is. No further occurrences "
          "will be created after it, but this task and its history are "
          "kept.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel future occurrences'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    await RepositoryScope.of(context)
        .notificationScheduler
        .cancelFutureOccurrences(task.id!);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    _showSnack('Future occurrences cancelled');
  }

  Future<void> _snooze(ReminderModel reminder) async {
    final choice = await showModalBottomSheet<_SnoozeChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => const _SnoozeOptionsSheet(),
    );
    if (choice == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    await RepositoryScope.of(context).notificationScheduler.snoozeReminder(
          reminder.id!,
          option: choice.option,
          customDuration: choice.customDuration,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    _showSnack('Reminder snoozed');
  }

  Future<void> _reschedule(TaskModel task, ReminderModel reminder) async {
    final initial = reminder.snoozedUntil ?? reminder.reminderTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;
    if (!mounted) return;

    final newTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() => _busy = true);
    final repos = RepositoryScope.of(context);
    if (task.recurrenceRuleId != null) {
      // Recurring: goes through the occurrence-aware path, which moves
      // just this one occurrence (and records it as such) without
      // shifting the rest of the series - see
      // ReminderEngine.rescheduleCurrentOccurrence.
      await repos.notificationScheduler.rescheduleOccurrence(
        task.id!,
        newTime,
      );
    } else {
      await repos.notificationScheduler
          .updateAndRescheduleReminder(reminder.id!, newTime);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    _showSnack('Reminder rescheduled');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: FutureBuilder<_TaskDetailsData?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const REmindLoadingState();
          }
          if (snapshot.hasError) {
            return REmindErrorState(
              message: 'Something went wrong loading this task.',
              onRetry: _reload,
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const REmindEmptyState(
              icon: Icons.task_outlined,
              title: 'This task no longer exists',
              message: 'It may have been deleted from another screen.',
            );
          }
          return Stack(
            children: [
              _buildBody(context, data),
              if (_busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .scrim
                        .withValues(alpha: 0.32),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, _TaskDetailsData data) {
    final task = data.task;
    final now = DateTime.now();
    final hasActiveSnooze = data.reminder != null &&
        data.reminder!.isEnabled &&
        data.reminder!.snoozedUntil != null &&
        data.reminder!.snoozedUntil!.isAfter(now);
    final displayStatus = TaskStatusCalculator.displayStatusFor(
      task,
      now: now,
      hasActiveSnooze: hasActiveSnooze,
    );
    final categoryColor = data.category == null
        ? null
        : (colorFromHex(data.category!.color) ??
            kDefaultCategoryColors[data.category!.name]);
    final isCompleted = task.status == TaskStatus.completed;
    final reminder = data.reminder;
    final canSnoozeOrReschedule = reminder != null && !isCompleted;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusBadge(status: displayStatus),
            PriorityBadge(priority: task.priority),
            if (data.category != null)
              Chip(
                label: Text(data.category!.name),
                backgroundColor: (categoryColor ??
                        Theme.of(context).colorScheme.secondaryContainer)
                    .withValues(alpha: 0.15),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (task.description != null && task.description!.isNotEmpty) ...[
          Text('Description', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(task.description!),
          const SizedBox(height: 20),
        ],
        Text('Due', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(task.dueDate == null
            ? 'No due date set'
            : formatDateTime(task.dueDate!)),
        const SizedBox(height: 20),
        if (data.recurrenceRule != null) ...[
          Text('Repeats', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.repeat,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(recurrenceSummary(data.recurrenceRule!)),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text('Tags', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        data.tags.isEmpty
            ? const Text('No tags')
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in data.tags)
                    Chip(
                      label: Text(tag.name),
                      backgroundColor: (colorFromHex(tag.color) ??
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest)
                          .withValues(alpha: 0.4),
                    ),
                ],
              ),
        const SizedBox(height: 20),
        Text('Reminder', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(_reminderInfoText(reminder)),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!isCompleted)
              FilledButton.icon(
                onPressed: _busy ? null : () => _complete(task),
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
              ),
            if (isCompleted)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _reopen(task),
                icon: const Icon(Icons.replay),
                label: const Text('Reopen'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _edit(task),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            if (canSnoozeOrReschedule)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _snooze(reminder),
                icon: const Icon(Icons.snooze_outlined),
                label: const Text('Snooze'),
              ),
            if (canSnoozeOrReschedule)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _reschedule(task, reminder),
                icon: const Icon(Icons.event_repeat_outlined),
                label: const Text('Reschedule'),
              ),
            if (task.recurrenceRuleId != null && !isCompleted)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _skipOccurrence(task),
                icon: const Icon(Icons.skip_next_outlined),
                label: const Text('Skip this occurrence'),
              ),
            if (task.recurrenceRuleId != null && !isCompleted)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _cancelFutureOccurrences(task),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Cancel future occurrences'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _delete(task),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ],
    );
  }

  String _reminderInfoText(ReminderModel? reminder) {
    if (reminder == null) return 'No reminder set';
    if (reminder.snoozedUntil != null &&
        reminder.snoozedUntil!.isAfter(DateTime.now())) {
      return 'Snoozed until ${formatDateTime(reminder.snoozedUntil!)}';
    }
    final base = 'Reminder set for ${formatDateTime(reminder.reminderTime)}';
    return reminder.isEnabled ? base : '$base (disabled)';
  }
}

class _TaskDetailsData {
  const _TaskDetailsData({
    required this.task,
    required this.category,
    required this.tags,
    required this.reminder,
    required this.recurrenceRule,
  });

  final TaskModel task;
  final CategoryModel? category;
  final List<TagModel> tags;
  final ReminderModel? reminder;
  final RecurrenceRuleModel? recurrenceRule;
}

/// What the user picked from [_SnoozeOptionsSheet]: a preset [option], plus
/// [customDuration] when [option] is [SnoozeOption.custom].
class _SnoozeChoice {
  const _SnoozeChoice(this.option, {this.customDuration});
  final SnoozeOption option;
  final Duration? customDuration;
}

/// Bottom sheet offering every preset in [SnoozeOption] plus a custom
/// duration entry, matching the spec's required snooze presets.
class _SnoozeOptionsSheet extends StatelessWidget {
  const _SnoozeOptionsSheet();

  static const _presets = [
    (SnoozeOption.fiveMinutes, '5 minutes'),
    (SnoozeOption.tenMinutes, '10 minutes'),
    (SnoozeOption.fifteenMinutes, '15 minutes'),
    (SnoozeOption.thirtyMinutes, '30 minutes'),
    (SnoozeOption.oneHour, '1 hour'),
    (SnoozeOption.tomorrow, 'Tomorrow, same time'),
  ];

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Snooze until',
    );
    if (picked == null) return;
    final now = DateTime.now();
    var target =
        DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    if (context.mounted) {
      Navigator.of(context).pop(
        _SnoozeChoice(SnoozeOption.custom,
            customDuration: target.difference(now)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(Icons.notifications_outlined, color: primary),
            ),
            const SizedBox(height: 12),
            Text('Snooze Reminder',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final preset in _presets)
              ListTile(
                leading: Icon(Icons.schedule_outlined, color: primary),
                title: Text(preset.$2),
                onTap: () =>
                    Navigator.of(context).pop(_SnoozeChoice(preset.$1)),
              ),
            ListTile(
              leading: Icon(Icons.edit_calendar_outlined, color: primary),
              title: const Text('Custom time...'),
              onTap: () => _pickCustom(context),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
