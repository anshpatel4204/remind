import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/utils/task_status_calculator.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import 'priority_badge.dart';
import 'status_badge.dart';

/// One row in any task list (the Tasks tab, Home's Today/Pinned sections,
/// Calendar's day view) - checkbox, title, priority, computed status,
/// category, tags, and due time, plus quick actions to complete, pin,
/// edit, and delete. Shared so every list in the app renders a task
/// identically rather than each screen growing its own slightly-different
/// copy.
class TaskListTile extends StatelessWidget {
  const TaskListTile({
    super.key,
    required this.task,
    required this.category,
    this.tags = const [],
    this.hasActiveSnooze = false,
    this.recurrenceLabel,
    required this.onTap,
    required this.onToggleComplete,
    required this.onTogglePin,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskModel task;
  final CategoryModel? category;
  final List<TagModel> tags;
  final bool hasActiveSnooze;

  /// A short recurrence summary (e.g. "Every day", "Every Monday") from
  /// [recurrenceSummary], or null for a non-recurring task. Passed in
  /// rather than computed here so this widget never has to know how to
  /// load a [RecurrenceRuleModel] itself - callers already load
  /// everything else about a task (category, tags) the same way.
  final String? recurrenceLabel;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;
  final VoidCallback onTogglePin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;
    final displayStatus = TaskStatusCalculator.displayStatusFor(
      task,
      now: DateTime.now(),
      hasActiveSnooze: hasActiveSnooze,
    );
    final categoryColor = category == null
        ? null
        : (colorFromHex(category!.color) ??
            kDefaultCategoryColors[category!.name]);
    final priorityColor = AppColors.priority[task.priority]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      // A thin priority-colored left edge so the list is scannable by
      // priority at a glance. This is a plain border decoration (not an
      // extra Row/Expanded layout) specifically so it never has to guess
      // its own height - a Row with CrossAxisAlignment.stretch here would
      // receive an unbounded height from the enclosing list and crash.
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isCompleted ? Colors.transparent : priorityColor,
              width: 4,
            ),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                    value: isCompleted, onChanged: (_) => onToggleComplete()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: isCompleted
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough)
                              : Theme.of(context).textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            PriorityBadge(priority: task.priority),
                            StatusBadge(status: displayStatus),
                            if (recurrenceLabel != null)
                              Chip(
                                avatar: Icon(Icons.repeat,
                                    size: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                                label: Text(recurrenceLabel!),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (category != null)
                              Chip(
                                label: Text(category!.name),
                                backgroundColor: (categoryColor ??
                                        Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer)
                                    .withValues(alpha: 0.15),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            for (final tag in tags)
                              Chip(
                                label: Text('#${tag.name}'),
                                backgroundColor: (colorFromHex(tag.color) ??
                                        Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest)
                                    .withValues(alpha: 0.3),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                        if (task.dueDate != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formatDateTime(task.dueDate!),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(task.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                      onPressed: onTogglePin,
                      tooltip: task.isPinned ? 'Unpin' : 'Pin',
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
