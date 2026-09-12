import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/tag_model.dart';
import '../../../../data/models/task_filter.dart';
import '../../../../data/models/task_model.dart';
import '../../../../core/utils/task_status_calculator.dart';
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

  static const _overdueFilter = TaskFilter(status: TaskDisplayStatus.overdue);
  static const _dueTodayFilter = TaskFilter(dueDateFilter: DueDateFilter.today);
  static const _completedFilter = TaskFilter(status: TaskDisplayStatus.completed);

  TaskFilter _upcomingFilter(DateTime now) {
    final startOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return TaskFilter(dueDateFilter: DueDateFilter.custom, customDueDateFrom: startOfTomorrow);
  }

  Future<_HomeData> _load() async {
    final repos = RepositoryScope.of(context);
    final now = DateTime.now();

    final overdue = await repos.taskRepository.getFilteredTasks(_overdueFilter, now: now);
    final dueToday = await repos.taskRepository.getFilteredTasks(_dueTodayFilter, now: now);
    final upcoming = await repos.taskRepository.getFilteredTasks(_upcomingFilter(now), now: now);
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
            return _HomeErrorView(onRetry: _reload);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
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
                    _StatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Overdue',
                      count: data.overdueCount,
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => _openFiltered(_overdueFilter),
                    ),
                    _StatCard(
                      icon: Icons.today_outlined,
                      label: 'Due today',
                      count: data.dueTodayTasks.length,
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () => _openFiltered(_dueTodayFilter),
                    ),
                    _StatCard(
                      icon: Icons.upcoming_outlined,
                      label: 'Upcoming',
                      count: data.upcomingCount,
                      color: Theme.of(context).colorScheme.tertiary,
                      onTap: () => _openFiltered(_upcomingFilter(now)),
                    ),
                    _StatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Completed',
                      count: data.completedCount,
                      color: Colors.green,
                      onTap: () => _openFiltered(_completedFilter),
                    ),
                  ],
                ),
                if (data.pinnedTasks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'Pinned', icon: Icons.push_pin),
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
                const _SectionHeader(title: "Today's tasks", icon: Icons.checklist_outlined),
                const SizedBox(height: 8),
                if (data.dueTodayTasks.isEmpty)
                  const _EmptyTodayView()
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _EmptyTodayView extends StatelessWidget {
  const _EmptyTodayView();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('No tasks for today 🎉', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Your schedule is clear.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            const Text('Something went wrong loading your dashboard.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
