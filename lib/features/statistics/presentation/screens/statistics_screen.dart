import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/statistics_calculator.dart';
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
/// of plain [Container]s and [LinearProgressIndicator]. The actual number
/// crunching lives in [StatisticsCalculator], kept separate so it can be
/// unit tested without a database or a widget tree.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

/// Bundles the pure [StatisticsData] with the category lookup table the
/// screen needs to render category names/colors - the latter is a display
/// concern (fetching category rows), not part of the calculation itself,
/// so it stays out of [StatisticsCalculator].
class _ScreenStats {
  const _ScreenStats({required this.data, required this.categoryById});

  final StatisticsData data;
  final Map<int, CategoryModel> categoryById;
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<_ScreenStats> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_ScreenStats> _load() async {
    final repos = RepositoryScope.of(context);
    final tasks = await repos.taskRepository.getAllTasks();
    final categories = await repos.categoryRepository.getAllCategories();

    return _ScreenStats(
      data: StatisticsCalculator.compute(tasks, now: DateTime.now()),
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
      body: FutureBuilder<_ScreenStats>(
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
          final screenStats = snapshot.data!;
          final data = screenStats.data;
          final categoryById = screenStats.categoryById;
          if (data.total == 0) {
            return const REmindEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'No data yet',
              message: 'Add some tasks to see your stats here.',
            );
          }

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
                      color: AppColors.success,
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
                    REmindStatCard(
                      icon: Icons.event_busy_outlined,
                      label: 'Missed',
                      count: data.missed,
                      color: Theme.of(context).colorScheme.outline,
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
                          value: data.completionRate,
                          minHeight: 10,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation(AppColors.success),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${(data.completionRate * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 28),
                const REmindSectionHeader(title: 'Completed', icon: Icons.event_available_outlined),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: REmindStatCard(
                        label: 'Today',
                        count: data.completedToday,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: REmindStatCard(
                        label: 'This week',
                        count: data.completedThisWeek,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: REmindStatCard(
                        label: 'This month',
                        count: data.completedThisMonth,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const REmindSectionHeader(
                  title: 'Tasks completed per day',
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
                            label: i == 6
                                ? 'Today'
                                : DateFormat('E').format(data.chartStart.add(Duration(days: i))),
                            value: data.completedPerDay[i],
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
                                    : (categoryById[entry.key]?.name ?? 'Unknown'),
                                value: entry.value,
                                color: entry.key == null
                                    ? Theme.of(context).colorScheme.outline
                                    : (colorFromHex(categoryById[entry.key]?.color) ??
                                        kDefaultCategoryColors[categoryById[entry.key]?.name] ??
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
                                              : (colorFromHex(categoryById[entry.key]?.color) ??
                                                  kDefaultCategoryColors[categoryById[entry.key]?.name] ??
                                                  Theme.of(context).colorScheme.primary),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.key == null
                                              ? 'Uncategorized'
                                              : (categoryById[entry.key]?.name ?? 'Unknown'),
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
