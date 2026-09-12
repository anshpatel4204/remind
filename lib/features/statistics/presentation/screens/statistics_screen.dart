import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../presentation/widgets/repository_scope.dart';

const Map<TaskPriority, Color> _priorityColors = {
  TaskPriority.low: Color(0xFF6C757D),
  TaskPriority.medium: Color(0xFF2E86AB),
  TaskPriority.high: Color(0xFFF77F00),
  TaskPriority.urgent: Color(0xFFE63946),
};

const Map<TaskPriority, String> _priorityLabels = {
  TaskPriority.low: 'Low',
  TaskPriority.medium: 'Medium',
  TaskPriority.high: 'High',
  TaskPriority.urgent: 'Urgent',
};

/// The Statistics tab: simple counts and breakdowns computed client-side
/// from [TaskRepository.getAllTasks] - no new repository methods, and no
/// charting package dependency, just custom bar/progress widgets built out
/// of plain [Container]s and [LinearProgressIndicator].
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<_StatsData> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_StatsData> _load() async {
    final repos = RepositoryScope.of(context);
    final tasks = await repos.taskRepository.getAllTasks();
    final categories = await repos.categoryRepository.getAllCategories();
    final now = DateTime.now();

    var completed = 0;
    var cancelled = 0;
    var overdue = 0;
    var pending = 0;

    final byPriority = <TaskPriority, int>{for (final p in TaskPriority.values) p: 0};
    final byCategory = <int?, int>{};

    for (final task in tasks) {
      final isOverdue = task.dueDate != null &&
          task.dueDate!.isBefore(now) &&
          task.status != TaskStatus.completed &&
          task.status != TaskStatus.cancelled;

      if (task.status == TaskStatus.completed) {
        completed++;
      } else if (task.status == TaskStatus.cancelled) {
        cancelled++;
      } else if (isOverdue) {
        overdue++;
      } else {
        pending++;
      }

      byPriority[task.priority] = (byPriority[task.priority] ?? 0) + 1;
      byCategory[task.categoryId] = (byCategory[task.categoryId] ?? 0) + 1;
    }

    return _StatsData(
      total: tasks.length,
      completed: completed,
      pending: pending,
      overdue: overdue,
      cancelled: cancelled,
      byPriority: byPriority,
      byCategory: byCategory,
      categoryById: {for (final c in categories) if (c.id != null) c.id!: c},
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<_StatsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StatisticsErrorView(onRetry: _reload);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.total == 0) {
            return const _EmptyStatisticsView();
          }
          final completionRate = data.completed / data.total;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.8,
                  children: [
                    _SummaryTile(label: 'Total', count: data.total, color: Theme.of(context).colorScheme.primary),
                    _SummaryTile(label: 'Completed', count: data.completed, color: Colors.green),
                    _SummaryTile(label: 'Pending', count: data.pending, color: Theme.of(context).colorScheme.tertiary),
                    _SummaryTile(label: 'Overdue', count: data.overdue, color: Theme.of(context).colorScheme.error),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Completion rate', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: completionRate,
                          minHeight: 10,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation(Colors.green),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${(completionRate * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 28),
                Text('By priority', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final priority in TaskPriority.values)
                  _BreakdownRow(
                    label: _priorityLabels[priority]!,
                    count: data.byPriority[priority] ?? 0,
                    total: data.total,
                    color: _priorityColors[priority]!,
                  ),
                const SizedBox(height: 28),
                Text('By category', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final entry in data.sortedCategoryCounts())
                  _BreakdownRow(
                    label: entry.key == null ? 'Uncategorized' : (data.categoryById[entry.key]?.name ?? 'Unknown'),
                    count: entry.value,
                    total: data.total,
                    color: entry.key == null
                        ? Theme.of(context).colorScheme.outline
                        : (colorFromHex(data.categoryById[entry.key]?.color) ??
                            kDefaultCategoryColors[data.categoryById[entry.key]?.name] ??
                            Theme.of(context).colorScheme.primary),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsData {
  const _StatsData({
    required this.total,
    required this.completed,
    required this.pending,
    required this.overdue,
    required this.cancelled,
    required this.byPriority,
    required this.byCategory,
    required this.categoryById,
  });

  final int total;
  final int completed;
  final int pending;
  final int overdue;
  final int cancelled;
  final Map<TaskPriority, int> byPriority;
  final Map<int?, int> byCategory;
  final Map<int, CategoryModel> categoryById;

  List<MapEntry<int?, int>> sortedCategoryCounts() {
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label)),
              Text('$count'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStatisticsView extends StatelessWidget {
  const _EmptyStatisticsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add some tasks to see your stats here.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsErrorView extends StatelessWidget {
  const _StatisticsErrorView({required this.onRetry});

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
            const Text('Something went wrong loading your statistics.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
