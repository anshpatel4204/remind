import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_filter.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../categories/presentation/screens/categories_screen.dart';
import '../../../tags/presentation/screens/tags_screen.dart';
import '../widgets/task_filter_sheet.dart';
import '../widgets/task_list_tile.dart';
import 'task_details_screen.dart';
import 'task_form_screen.dart';

/// The Tasks tab: lists tasks (filtered/sorted per [TaskFilter]), with
/// quick actions to complete, pin, edit, and delete, a FAB to add a new
/// one, and entry points to filter/sort the list and manage categories/tags.
///
/// [initialFilter] lets another screen (e.g. Home's stat cards) deep-link
/// into a specific view - "show me what's overdue" - by pushing this
/// screen already filtered, without either screen needing to share any
/// other state.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.initialFilter});

  final TaskFilter? initialFilter;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late Future<_TaskListData> _future;
  bool _initialized = false;
  late TaskFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? const TaskFilter();
  }

  // Loading the task list depends on RepositoryScope.of(context), which
  // (via dependOnInheritedWidgetOfExactType) cannot be called from
  // initState() - it must wait until didChangeDependencies(), once this
  // element is actually linked into the widget tree.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_TaskListData> _load() async {
    final repos = RepositoryScope.of(context);
    final tasks = await repos.taskRepository.getFilteredTasks(_filter);
    final categories = await repos.categoryRepository.getAllCategories();
    final tags = await repos.tagRepository.getAllTags();
    final categoryById = {for (final c in categories) if (c.id != null) c.id!: c};

    final now = DateTime.now();
    final tagsByTaskId = <int, List<TagModel>>{};
    final activeSnoozeTaskIds = <int>{};
    for (final task in tasks) {
      final id = task.id!;
      tagsByTaskId[id] = await repos.taskRepository.getTagsForTask(id);
      final reminders = await repos.reminderRepository.getRemindersForTask(id);
      final hasActiveSnooze = reminders.any(
        (r) => r.isEnabled && r.snoozedUntil != null && r.snoozedUntil!.isAfter(now),
      );
      if (hasActiveSnooze) activeSnoozeTaskIds.add(id);
    }

    return _TaskListData(
      tasks: tasks,
      categoryById: categoryById,
      categories: categories,
      tags: tags,
      tagsByTaskId: tagsByTaskId,
      activeSnoozeTaskIds: activeSnoozeTaskIds,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openAddTask() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TaskFormScreen()),
    );
    _reload();
  }

  Future<void> _openDetails(TaskModel task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: task.id!)),
    );
    _reload();
  }

  Future<void> _openEdit(TaskModel task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskFormScreen(existingTask: task)),
    );
    _reload();
  }

  Future<void> _toggleComplete(TaskModel task) async {
    final repos = RepositoryScope.of(context);
    if (task.status == TaskStatus.completed) {
      await repos.taskRepository.reopenTask(task.id!);
    } else {
      // Goes through notificationScheduler (not taskRepository directly)
      // so the task's reminder notification(s) are cancelled - and, for a
      // recurring task, rescheduled for the next occurrence - rather than
      // firing again for a task that's already done.
      await repos.notificationScheduler.completeTask(task.id!);
    }
    _reload();
  }

  Future<void> _togglePin(TaskModel task) async {
    await RepositoryScope.of(context).taskRepository.setPinned(task.id!, !task.isPinned);
    _reload();
  }

  Future<void> _confirmDelete(TaskModel task) async {
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
    final repos = RepositoryScope.of(context);
    await repos.notificationScheduler.cancelNotificationsForTask(task.id!);
    await repos.taskRepository.deleteTask(task.id!);
    if (!mounted) return;
    _reload();
  }

  Future<void> _openFilterSheet(_TaskListData data) async {
    final result = await showTaskFilterSheet(
      context,
      current: _filter,
      categories: data.categories,
      tags: data.tags,
    );
    if (result == null) return;
    setState(() => _filter = result);
    _reload();
  }

  void _clearFilters() {
    setState(() => _filter = const TaskFilter());
    _reload();
  }

  Future<void> _openManage(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          FutureBuilder<_TaskListData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return IconButton(
                icon: Icon(_filter.hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
                tooltip: 'Filter & sort',
                onPressed: data == null ? null : () => _openFilterSheet(data),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Manage',
            onSelected: (value) {
              if (value == 'categories') _openManage(const CategoriesScreen());
              if (value == 'tags') _openManage(const TagsScreen());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'categories', child: Text('Manage categories')),
              PopupMenuItem(value: 'tags', child: Text('Manage tags')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_TaskListData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _TaskListErrorView(onRetry: _reload);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return Column(
            children: [
              if (_filter.hasActiveFilters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 16),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Filters active', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(onPressed: _clearFilters, child: const Text('Clear')),
                    ],
                  ),
                ),
              Expanded(
                child: data.tasks.isEmpty
                    ? (_filter.hasActiveFilters
                        ? _NoMatchingTasksView(onClearFilters: _clearFilters)
                        : _EmptyTasksView(onAddTask: _openAddTask))
                    : RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: data.tasks.length,
                          itemBuilder: (context, index) {
                            final task = data.tasks[index];
                            final category =
                                task.categoryId == null ? null : data.categoryById[task.categoryId];
                            return TaskListTile(
                              task: task,
                              category: category,
                              tags: data.tagsByTaskId[task.id] ?? const [],
                              hasActiveSnooze: data.activeSnoozeTaskIds.contains(task.id),
                              onTap: () => _openDetails(task),
                              onToggleComplete: () => _toggleComplete(task),
                              onTogglePin: () => _togglePin(task),
                              onEdit: () => _openEdit(task),
                              onDelete: () => _confirmDelete(task),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'tasks-add-task-fab',
        onPressed: _openAddTask,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TaskListData {
  const _TaskListData({
    required this.tasks,
    required this.categoryById,
    required this.categories,
    required this.tags,
    required this.tagsByTaskId,
    required this.activeSnoozeTaskIds,
  });

  final List<TaskModel> tasks;
  final Map<int, CategoryModel> categoryById;
  final List<CategoryModel> categories;
  final List<TagModel> tags;
  final Map<int, List<TagModel>> tagsByTaskId;
  final Set<int> activeSnoozeTaskIds;
}

class _EmptyTasksView extends StatelessWidget {
  const _EmptyTasksView({required this.onAddTask});

  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppConstants.brandLogoAsset, width: 96, height: 96),
            const SizedBox(height: 16),
            Text('No tasks yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first task.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddTask,
              icon: const Icon(Icons.add),
              label: const Text('Add task'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatchingTasksView extends StatelessWidget {
  const _NoMatchingTasksView({required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No tasks match these filters', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Try a different filter, or clear them to see everything.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onClearFilters, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

class _TaskListErrorView extends StatelessWidget {
  const _TaskListErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Something went wrong loading your tasks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
