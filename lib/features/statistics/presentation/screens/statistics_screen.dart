import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/enums.dart';
import '../../../../presentation/widgets/remind_bar_chart.dart';
import '../../../../presentation/widgets/remind_donut_chart.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/remind_section_header.dart';
import '../../../../presentation/widgets/remind_stat_card.dart';
import '../../../../presentation/widgets/repository_scope.dart';

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

    // Monday-start week containing `now`, for the "Tasks Completed" chart -
    // real completedAt data, not a fabricated trend.
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final completedByWeekday = List<int>.filled(7, 0);

    for (final task in tasks) {
      final isOverdue = task.dueDate != null &&
          task.dueDate!.isBefore(now) &&
          task.status != TaskStatus.completed &&
          task.status != TaskStatus.cancelled;

      if (task.status == TaskStatus.completed) {
        completed++;
        final completedAt = task.completedAt;
        if (completedAt != null && !completedAt.isBefore(weekStart) && completedAt.isBefore(weekEnd)) {
          completedByWeekday[completedAt.weekday - 1]++;
        }
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
      completedByWeekday: completedByWeekday,
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
            return REmindErrorState(
              message: 'Something went wrong loading your statistics.',
              onRetry: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const REmindLoadingState();
          }
          final data = snapshot.data!;
          if (data.total == 0) {
            return const REmindEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'No data yet',
              message: 'Add some tasks to see your stats here.',
            );
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
                  childAspectRatio: 1.3,
                  children: [
                    REmindStatCard(
                      icon: Icons.list_alt_outlined,
                      label: 'Total',
                      count: data.total,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    REmindStatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Completed',
                      count: data.completed,
                      color: Colors.green,
                    ),
                    REmindStatCard(
                      icon: Icons.schedule_outlined,
                      label: 'Pending',
                      count: data.pending,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    REmindStatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Overdue',
                      count: data.overdue,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const REmindSectionHeader(title: 'Completion rate', icon: Icons.trending_up_outlined),
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
                const REmindSectionHeader(
                  title: 'Tasks Completed',
                  icon: Icons.stacked_bar_chart_outlined,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: REmindBarChart(
                      values: [
                        for (var i = 0; i < 7; i++)
                          BarValue(
                            label: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                            value: data.completedByWeekday[i],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const REmindSectionHeader(title: 'Category Breakdown', icon: Icons.category_outlined),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        REmindDonutChart(
                          centerLabel: '${data.total}',
                          segments: [
                            for (final entry in data.sortedCategoryCounts())
                              DonutSegment(
                                label: entry.key == null
                                    ? 'Uncategorized'
                                    : (data.categoryById[entry.key]?.name ?? 'Unknown'),
                                value: entry.value,
                                color: entry.key == null
                                    ? Theme.of(context).colorScheme.outline
                                    : (colorFromHex(data.categoryById[entry.key]?.color) ??
                                        kDefaultCategoryColors[data.categoryById[entry.key]?.name] ??
                                        Theme.of(context).colorScheme.primary),
                              ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final entry in data.sortedCategoryCounts())
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: entry.key == null
                                              ? Theme.of(context).colorScheme.outline
                                              : (colorFromHex(data.categoryById[entry.key]?.color) ??
                                                  kDefaultCategoryColors[data.categoryById[entry.key]?.name] ??
                                                  Theme.of(context).colorScheme.primary),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.key == null
                                              ? 'Uncategorized'
                                              : (data.categoryById[entry.key]?.name ?? 'Unknown'),
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ),
                                      Text(
                                        '${data.total == 0 ? 0 : (entry.value / data.total * 100).round()}%',
                                        style: Theme.of(context).textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const REmindSectionHeader(title: 'By priority', icon: Icons.flag_outlined),
                const SizedBox(height: 12),
                for (final priority in TaskPriority.values)
                  _BreakdownRow(
                    label: AppColors.priorityLabel[priority]!,
                    count: data.byPriority[priority] ?? 0,
                    total: data.total,
                    color: AppColors.priority[priority]!,
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
    required this.completedByWeekday,
  });

  final int total;
  final int completed;
  final int pending;
  final int overdue;
  final int cancelled;
  final Map<TaskPriority, int> byPriority;
  final Map<int?, int> byCategory;
  final Map<int, CategoryModel> categoryById;

  /// Completed-task counts for the current week, Monday first - real data
  /// from each task's `completedAt`, used by the "Tasks Completed" chart.
  final List<int> completedByWeekday;

  List<MapEntry<int?, int>> sortedCategoryCounts() {
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries;
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
