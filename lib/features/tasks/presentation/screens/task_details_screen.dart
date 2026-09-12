import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/task_status_calculator.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/reminder_model.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../widgets/priority_badge.dart';
import '../widgets/status_badge.dart';
import 'task_form_screen.dart';

/// Full detail view for a single task: every field, its reminder (if any),
/// and the Complete/Reopen/Edit/Delete actions.
class TaskDetailsScreen extends StatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId});

  final int taskId;

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  late Future<_TaskDetailsData?> _future;
  bool _initialized = false;

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

    final category =
        task.categoryId == null ? null : await repos.categoryRepository.getCategory(task.categoryId!);
    final tags = await repos.taskRepository.getTagsForTask(task.id!);
    final reminders = await repos.reminderRepository.getRemindersForTask(task.id!);

    return _TaskDetailsData(
      task: task,
      category: category,
      tags: tags,
      reminder: reminders.isEmpty ? null : reminders.first,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _complete(TaskModel task) async {
    await RepositoryScope.of(context).taskRepository.completeTask(task.id!);
    _reload();
  }

  Future<void> _reopen(TaskModel task) async {
    await RepositoryScope.of(context).taskRepository.reopenTask(task.id!);
    _reload();
  }

  Future<void> _edit(TaskModel task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: task)),
    );
    _reload();
  }

  Future<void> _delete(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be permanently deleted, along with its reminder.'),
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
    if (confirmed != true) return;
    if (!mounted) return;
    await RepositoryScope.of(context).taskRepository.deleteTask(task.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: FutureBuilder<_TaskDetailsData?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: Text('This task no longer exists.'));
          }
          return _buildBody(context, data);
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
        : (colorFromHex(data.category!.color) ?? kDefaultCategoryColors[data.category!.name]);
    final isCompleted = task.status == TaskStatus.completed;

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
                backgroundColor:
                    (categoryColor ?? Theme.of(context).colorScheme.secondaryContainer)
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
        Text(task.dueDate == null ? 'No due date set' : formatDateTime(task.dueDate!)),
        const SizedBox(height: 20),
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
                              Theme.of(context).colorScheme.surfaceContainerHighest)
                          .withValues(alpha: 0.4),
                    ),
                ],
              ),
        const SizedBox(height: 20),
        Text('Reminder', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(_reminderInfoText(data.reminder)),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!isCompleted)
              FilledButton.icon(
                onPressed: () => _complete(task),
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
              ),
            if (isCompleted)
              OutlinedButton.icon(
                onPressed: () => _reopen(task),
                icon: const Icon(Icons.replay),
                label: const Text('Reopen'),
              ),
            OutlinedButton.icon(
              onPressed: () => _edit(task),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(task),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }

  String _reminderInfoText(ReminderModel? reminder) {
    if (reminder == null) return 'No reminder set';
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
  });

  final TaskModel task;
  final CategoryModel? category;
  final List<TagModel> tags;
  final ReminderModel? reminder;
}
