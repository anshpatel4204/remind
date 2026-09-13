import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_filter.dart';
import '../../../../data/models/task_model.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/remind_section_header.dart';
import '../../../../presentation/widgets/remind_stat_card.dart';
import '../../../../presentation/widgets/repository_scope.dart';
import '../../../tasks/presentation/screens/task_details_screen.dart';
import '../../../tasks/presentation/screens/task_form_screen.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';
import '../../../tasks/presentation/widgets/task_list_tile.dart';

final DateFormat _fullDateFormat = DateFormat('EEEE, MMMM d');

/// The Home tab: a dashboard giving a quick, personal-feeling snapshot of
/// the day - a greeting, today's date, at-a-glance counts (Overdue/Due
/// today/Upcoming/Completed), pinned tasks, and today's task list. Every
/// count and list here is produced by [TaskRepository.getFilteredTasks]
/// with the same [TaskFilter] shortcuts the Tasks tab already uses, so
/// tapping a stat card opens the Tasks tab pre-filtered to exactly what
/// the card counted - no separate aggregation logic to keep in sync.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  // These reuse the canonical presets in TaskFilterPresets rather than
  // defining their own TaskFilter, so "what counts as Overdue/Upcoming/
  // etc." can't quietly drift out of sync with the Tasks tab's quick
  // filter chips, which draw from the same presets.
  static const _overdueFilter = TaskFilterPresets.overdue;
  static const _dueTodayFilter = TaskFilterPresets.today;
  static const _completedFilter = TaskFilterPresets.completed;
  static const _upcomingFilter = TaskFilterPresets.upcoming;

  Future<_HomeData> _load() async {
    final repos = RepositoryScope.of(context);
    final now = DateTime.now();

    final overdue = await repos.taskRepository.getFilteredTasks(_overdueFilter, now: now);
    final dueToday = await repos.taskRepository.getFilteredTasks(_dueTodayFilter, now: now);
    final upcoming = await repos.taskRepository.getFilteredTasks(_upcomingFilter, now: now);
    final completed = await repos.taskRepository.getFilteredTasks(_completedFilter, now: now);
    final pinnedAll = await repos.taskRepository.getAllTasks(pinnedOnly: true);
    final pinned = pinnedAll
        .where((t) => t.status != TaskStatus.completed && t.status != TaskStatus.cancelled)
        .toList();

    // Today's tasks and pinned tasks are the only ones actually rendered as
    // tiles, so tag/snooze lookups only need to run for those - not every
    // task in every stat bucket.
    final tileTasks = <TaskModel>{...dueToday, ...pinned}.toList();
    final categories = await repos.categoryRepository.getAllCategories();
    final categoryById = {for (final c in categories) if (c.id != null) c.id!: c};

    final tagsByTaskId = <int, List<TagModel>>{};
    final activeSnoozeTaskIds = <int>{};
    for (final task in tileTasks) {
      final id = task.id!;
      tagsByTaskId[id] = await repos.taskRepository.getTagsForTask(id);
      final reminders = await repos.reminderRepository.getRemindersForTask(id);
      final hasActiveSnooze = reminders.any(
        (r) => r.isEnabled && r.snoozedUntil != null && r.snoozedUntil!.isAfter(now),
      );
      if (hasActiveSnooze) activeSnoozeTaskIds.add(id);
    }

    return _HomeData(
      overdueCount: overdue.length,
      dueTodayTasks: dueToday,
      upcomingCount: upcoming.length,
      completedCount: completed.length,
      pinnedTasks: pinned,
      categoryById: categoryById,
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

  void _openFiltered(TaskFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TasksScreen(initialFilter: filter)),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return REmindErrorState(
              message: 'Something went wrong loading your dashboard.',
              onRetry: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const REmindLoadingState();
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(_greeting(now), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  _fullDateFormat.format(now),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: [
                    REmindStatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Overdue',
                      count: data.overdueCount,
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => _openFiltered(_overdueFilter),
                    ),
                    REmindStatCard(
                      icon: Icons.today_outlined,
                      label: 'Due today',
                      count: data.dueTodayTasks.length,
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () => _openFiltered(_dueTodayFilter),
                    ),
                    REmindStatCard(
                      icon: Icons.upcoming_outlined,
                      label: 'Upcoming',
                      count: data.upcomingCount,
                      color: Theme.of(context).colorScheme.tertiary,
                      onTap: () => _openFiltered(_upcomingFilter),
                    ),
                    REmindStatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Completed',
                      count: data.completedCount,
                      color: AppColors.success,
                      onTap: () => _openFiltered(_completedFilter),
                    ),
                  ],
                ),
                if (data.pinnedTasks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const REmindSectionHeader(title: 'Pinned', icon: Icons.push_pin),
                  const SizedBox(height: 8),
                  for (final task in data.pinnedTasks)
                    TaskListTile(
                      task: task,
                      category: task.categoryId == null ? null : data.categoryById[task.categoryId],
                      tags: data.tagsByTaskId[task.id] ?? const [],
                      hasActiveSnooze: data.activeSnoozeTaskIds.contains(task.id),
                      onTap: () => _openDetails(task),
                      onToggleComplete: () => _toggleComplete(task),
                      onTogglePin: () => _togglePin(task),
                      onEdit: () => _openEdit(task),
                      onDelete: () => _confirmDelete(task),
                    ),
                ],
                const SizedBox(height: 24),
                const REmindSectionHeader(title: "Today's tasks", icon: Icons.checklist_outlined),
                const SizedBox(height: 8),
                if (data.dueTodayTasks.isEmpty)
                  const REmindEmptyState(
                    compact: true,
                    title: 'No tasks for today 🎉',
                    message: 'Your schedule is clear.',
                  )
                else
                  for (final task in data.dueTodayTasks)
                    TaskListTile(
                      task: task,
                      category: task.categoryId == null ? null : data.categoryById[task.categoryId],
                      tags: data.tagsByTaskId[task.id] ?? const [],
                      hasActiveSnooze: data.activeSnoozeTaskIds.contains(task.id),
                      onTap: () => _openDetails(task),
                      onToggleComplete: () => _toggleComplete(task),
                      onTogglePin: () => _togglePin(task),
                      onEdit: () => _openEdit(task),
                      onDelete: () => _confirmDelete(task),
                    ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home-add-task-fab',
        onPressed: _openAddTask,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.overdueCount,
    required this.dueTodayTasks,
    required this.upcomingCount,
    required this.completedCount,
    required this.pinnedTasks,
    required this.categoryById,
    required this.tagsByTaskId,
    required this.activeSnoozeTaskIds,
  });

  final int overdueCount;
  final List<TaskModel> dueTodayTasks;
  final int upcomingCount;
  final int completedCount;
  final List<TaskModel> pinnedTasks;
  final Map<int, CategoryModel> categoryById;
  final Map<int, List<TagModel>> tagsByTaskId;
  final Set<int> activeSnoozeTaskIds;
}

