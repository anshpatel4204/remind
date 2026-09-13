import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../tasks/presentation/screens/task_details_screen.dart';
import '../../../tasks/presentation/screens/task_form_screen.dart';
import '../../../tasks/presentation/widgets/task_list_tile.dart';

/// A dedicated search screen: title/description/tag search across every
/// task, backed by [TaskRepository.searchTasks] - a real SQL query, not an
/// in-memory scan - so it stays fast and never loads the whole task table
/// just to filter it client-side.
///
/// Typing is debounced (250ms) so a fast typist doesn't fire a query per
/// keystroke; the debounce timer is always cancelled in [dispose].
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<_SearchResults>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _future = _query.isEmpty ? null : _search(_query);
      });
    });
  }

  Future<_SearchResults> _search(String query) async {
    final repos = RepositoryScope.of(context);
    final tasks = await repos.taskRepository.searchTasks(query);

    final categories = await repos.categoryRepository.getAllCategories();
    final categoryById = {
      for (final c in categories)
        if (c.id != null) c.id!: c
    };

    final now = DateTime.now();
    final tagsByTaskId = <int, List<TagModel>>{};
    final activeSnoozeTaskIds = <int>{};
    for (final task in tasks) {
      final id = task.id!;
      tagsByTaskId[id] = await repos.taskRepository.getTagsForTask(id);
      final reminders = await repos.reminderRepository.getRemindersForTask(id);
      final hasActiveSnooze = reminders.any(
        (r) =>
            r.isEnabled &&
            r.snoozedUntil != null &&
            r.snoozedUntil!.isAfter(now),
      );
      if (hasActiveSnooze) activeSnoozeTaskIds.add(id);
    }

    return _SearchResults(
      tasks: tasks,
      categoryById: categoryById,
      tagsByTaskId: tagsByTaskId,
      activeSnoozeTaskIds: activeSnoozeTaskIds,
    );
  }

  void _reload() {
    if (_query.isEmpty) return;
    setState(() => _future = _search(_query));
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
      await repos.notificationScheduler.completeTask(task.id!);
    }
    _reload();
  }

  Future<void> _togglePin(TaskModel task) async {
    await RepositoryScope.of(context)
        .taskRepository
        .setPinned(task.id!, !task.isPinned);
    _reload();
  }

  Future<void> _confirmDelete(TaskModel task) async {
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
    if (confirmed != true) return;
    if (!mounted) return;
    final repos = RepositoryScope.of(context);
    await repos.notificationScheduler.cancelNotificationsForTask(task.id!);
    await repos.taskRepository.deleteTask(task.id!);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('searchScreenField'),
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search title, description, tags...',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _query = '';
                        _future = null;
                      });
                    },
                  ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? const REmindEmptyState(
              icon: Icons.search,
              title: 'Search your tasks',
              message: 'Find tasks by title, description, or tag.',
            )
          : FutureBuilder<_SearchResults>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return REmindErrorState(
                    message: 'Something went wrong running that search.',
                    onRetry: _reload,
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const REmindLoadingState();
                }
                final results = snapshot.data;
                if (results == null || results.tasks.isEmpty) {
                  return REmindEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No results for "$_query"',
                    message: 'Try a different title, description word, or tag.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: results.tasks.length,
                  itemBuilder: (context, index) {
                    final task = results.tasks[index];
                    final category = task.categoryId == null
                        ? null
                        : results.categoryById[task.categoryId];
                    return TaskListTile(
                      task: task,
                      category: category,
                      tags: results.tagsByTaskId[task.id] ?? const [],
                      hasActiveSnooze:
                          results.activeSnoozeTaskIds.contains(task.id),
                      onTap: () => _openDetails(task),
                      onToggleComplete: () => _toggleComplete(task),
                      onTogglePin: () => _togglePin(task),
                      onEdit: () => _openEdit(task),
                      onDelete: () => _confirmDelete(task),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SearchResults {
  const _SearchResults({
    required this.tasks,
    required this.categoryById,
    required this.tagsByTaskId,
    required this.activeSnoozeTaskIds,
  });

  final List<TaskModel> tasks;
  final Map<int, CategoryModel> categoryById;
  final Map<int, List<TagModel>> tagsByTaskId;
  final Set<int> activeSnoozeTaskIds;
}
