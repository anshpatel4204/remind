import 'package:flutter/material.dart';

import '../../../../core/utils/task_status_calculator.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_filter.dart';

/// Shows the Task List's filter-and-sort bottom sheet, seeded with
/// [current], and returns the [TaskFilter] the user applied - or null if
/// they dismissed the sheet without tapping Apply.
Future<TaskFilter?> showTaskFilterSheet(
  BuildContext context, {
  required TaskFilter current,
  required List<CategoryModel> categories,
  required List<TagModel> tags,
}) {
  return showModalBottomSheet<TaskFilter>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _TaskFilterSheet(current: current, categories: categories, tags: tags),
  );
}

class _TaskFilterSheet extends StatefulWidget {
  const _TaskFilterSheet(
      {required this.current, required this.categories, required this.tags});

  final TaskFilter current;
  final List<CategoryModel> categories;
  final List<TagModel> tags;

  @override
  State<_TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<_TaskFilterSheet> {
  TaskDisplayStatus? _status;
  int? _categoryId;
  TaskPriority? _priority;
  int? _tagId;
  DueDateFilter _dueDateFilter = DueDateFilter.any;
  TaskSortOption _sortBy = TaskSortOption.dueDate;
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    _status = widget.current.status;
    _categoryId = widget.current.categoryId;
    _priority = widget.current.priority;
    _tagId = widget.current.tagId;
    _dueDateFilter = widget.current.dueDateFilter;
    _sortBy = widget.current.sortBy;
    _ascending = widget.current.ascending;
  }

  void _clear() {
    setState(() {
      _status = null;
      _categoryId = null;
      _priority = null;
      _tagId = null;
      _dueDateFilter = DueDateFilter.any;
      _sortBy = TaskSortOption.dueDate;
      _ascending = true;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      TaskFilter(
        status: _status,
        categoryId: _categoryId,
        priority: _priority,
        tagId: _tagId,
        dueDateFilter: _dueDateFilter,
        sortBy: _sortBy,
        ascending: _ascending,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Filter & sort',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  TextButton(onPressed: _clear, child: const Text('Clear all')),
                ],
              ),
              const SizedBox(height: 8),
              const _SectionLabel('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _categoryId == null,
                    onSelected: (_) => setState(() => _categoryId = null),
                  ),
                  for (final category in widget.categories)
                    ChoiceChip(
                      label: Text(category.name),
                      selected: _categoryId == category.id,
                      onSelected: (_) =>
                          setState(() => _categoryId = category.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('Tag'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _tagId == null,
                    onSelected: (_) => setState(() => _tagId = null),
                  ),
                  for (final tag in widget.tags)
                    ChoiceChip(
                      label: Text('#${tag.name}'),
                      selected: _tagId == tag.id,
                      onSelected: (_) => setState(() => _tagId = tag.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('Priority'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _priority == null,
                    onSelected: (_) => setState(() => _priority = null),
                  ),
                  for (final priority in TaskPriority.values)
                    ChoiceChip(
                      label: Text(_priorityLabel(priority)),
                      selected: _priority == priority,
                      onSelected: (_) => setState(() => _priority = priority),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('Status'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _status == null,
                    onSelected: (_) => setState(() => _status = null),
                  ),
                  for (final status in TaskDisplayStatus.values)
                    ChoiceChip(
                      label: Text(_statusLabel(status)),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('Due date'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    DueDateFilter.any,
                    DueDateFilter.today,
                    DueDateFilter.tomorrow,
                    DueDateFilter.thisWeek,
                    DueDateFilter.thisMonth,
                    DueDateFilter.upcoming,
                    DueDateFilter.overdue,
                    DueDateFilter.noDueDate,
                  ])
                    ChoiceChip(
                      label: Text(_dueDateFilterLabel(option)),
                      selected: _dueDateFilter == option,
                      onSelected: (_) =>
                          setState(() => _dueDateFilter = option),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Sort by'),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TaskSortOption>(
                      initialValue: _sortBy,
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                      items: TaskSortOption.values
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(_sortLabel(s))))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _sortBy = value ?? _sortBy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => setState(() => _ascending = !_ascending),
                    tooltip: _ascending ? 'Ascending' : 'Descending',
                    icon: Icon(
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child:
                    FilledButton(onPressed: _apply, child: const Text('Apply')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _priorityLabel(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
      case TaskPriority.urgent:
        return 'Urgent';
    }
  }

  String _statusLabel(TaskDisplayStatus status) {
    switch (status) {
      case TaskDisplayStatus.pending:
        return 'Pending';
      case TaskDisplayStatus.inProgress:
        return 'In Progress';
      case TaskDisplayStatus.completed:
        return 'Completed';
      case TaskDisplayStatus.overdue:
        return 'Overdue';
      case TaskDisplayStatus.snoozed:
        return 'Snoozed';
      case TaskDisplayStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _dueDateFilterLabel(DueDateFilter filter) {
    switch (filter) {
      case DueDateFilter.any:
        return 'Any time';
      case DueDateFilter.today:
        return 'Today';
      case DueDateFilter.tomorrow:
        return 'Tomorrow';
      case DueDateFilter.thisWeek:
        return 'This week';
      case DueDateFilter.thisMonth:
        return 'This month';
      case DueDateFilter.upcoming:
        return 'Upcoming';
      case DueDateFilter.overdue:
        return 'Overdue';
      case DueDateFilter.noDueDate:
        return 'No due date';
      case DueDateFilter.custom:
        return 'Custom';
    }
  }

  String _sortLabel(TaskSortOption sort) {
    switch (sort) {
      case TaskSortOption.dueDate:
        return 'Due date';
      case TaskSortOption.priority:
        return 'Priority';
      case TaskSortOption.createdDate:
        return 'Created date';
      case TaskSortOption.alphabetical:
        return 'Alphabetical';
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
