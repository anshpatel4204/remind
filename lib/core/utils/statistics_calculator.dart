import '../../data/models/enums.dart';
import '../../data/models/task_model.dart';

/// The computed numbers behind the Statistics screen - see
/// [StatisticsCalculator.compute] for exactly how each is derived.
class StatisticsData {
  const StatisticsData({
    required this.total,
    required this.completed,
    required this.pending,
    required this.overdue,
    required this.missed,
    required this.cancelled,
    required this.completedToday,
    required this.completedThisWeek,
    required this.completedThisMonth,
    required this.byPriority,
    required this.byCategory,
    required this.completedPerDay,
    required this.chartStart,
  });

  final int total;
  final int completed;
  final int pending;

  /// Still open (pending/in progress) tasks whose due date has already
  /// passed - can still be completed late.
  final int overdue;

  /// Cancelled tasks whose due date had already passed - the deadline was
  /// never met and, unlike [overdue], never will be. See
  /// [StatisticsCalculator.compute] for the exact rule.
  final int missed;
  final int cancelled;

  final int completedToday;
  final int completedThisWeek;
  final int completedThisMonth;

  final Map<TaskPriority, int> byPriority;

  /// Task count keyed by category id; a null key means "uncategorized".
  final Map<int?, int> byCategory;

  /// Completed-task counts for the last 7 calendar days, oldest first,
  /// ending today - real data from each task's `completedAt`, used by the
  /// "Tasks completed per day" chart.
  final List<int> completedPerDay;

  /// The calendar day [completedPerDay]'s first entry corresponds to.
  final DateTime chartStart;

  double get completionRate => total == 0 ? 0 : completed / total;

  List<MapEntry<int?, int>> sortedCategoryCounts() {
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}

/// Pure computation behind the Statistics screen.
///
/// Takes the raw task list (plus the current moment) and derives every
/// count and chart series the screen shows. Kept free of
/// BuildContext/repositories/Flutter so it can be unit tested directly
/// with plain [TaskModel]s, the same way [TaskStatusCalculator] and
/// [RecurrenceCalculator] are.
class StatisticsCalculator {
  const StatisticsCalculator._();

  static StatisticsData compute(List<TaskModel> tasks,
      {required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);

    var completed = 0;
    var cancelled = 0;
    var overdue = 0;
    var missed = 0;
    var pending = 0;
    var completedToday = 0;
    var completedThisWeek = 0;
    var completedThisMonth = 0;

    final byPriority = <TaskPriority, int>{
      for (final p in TaskPriority.values) p: 0
    };
    final byCategory = <int?, int>{};

    // Monday-start week containing `today`, for the "completed this week"
    // stat - a calendar week, not just "the last 7 days".
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month, 1);

    // Rolling last 7 calendar days (today plus the 6 before it), for the
    // "Tasks completed per day" chart - unlike a fixed Mon-Sun week, this
    // never shows empty future days and always has a bar for "today" in
    // the same place, whatever day of the week it is.
    final chartStart = today.subtract(const Duration(days: 6));
    final completedPerDay = List<int>.filled(7, 0);

    for (final task in tasks) {
      final isPastDue = task.dueDate != null && task.dueDate!.isBefore(now);

      if (task.status == TaskStatus.completed) {
        completed++;
        final completedAt = task.completedAt;
        if (completedAt != null) {
          if (!completedAt.isBefore(today)) {
            completedToday++;
          }
          if (!completedAt.isBefore(weekStart)) {
            completedThisWeek++;
          }
          if (!completedAt.isBefore(monthStart)) {
            completedThisMonth++;
          }
          final completedDay =
              DateTime(completedAt.year, completedAt.month, completedAt.day);
          final dayIndex = completedDay.difference(chartStart).inDays;
          if (dayIndex >= 0 && dayIndex < 7) {
            completedPerDay[dayIndex]++;
          }
        }
      } else if (task.status == TaskStatus.cancelled) {
        cancelled++;
        // A cancelled task whose deadline had already passed is counted as
        // "missed" - the deadline was never met and, unlike an overdue
        // task, never will be. A cancelled task with no due date, or one
        // cancelled before its due date arrived, isn't a missed deadline.
        if (isPastDue) {
          missed++;
        }
      } else if (isPastDue) {
        // Still open (pending/in progress) and past its due date - can
        // still be completed late, so it's overdue rather than missed.
        overdue++;
      } else {
        pending++;
      }

      byPriority[task.priority] = (byPriority[task.priority] ?? 0) + 1;
      byCategory[task.categoryId] = (byCategory[task.categoryId] ?? 0) + 1;
    }

    return StatisticsData(
      total: tasks.length,
      completed: completed,
      pending: pending,
      overdue: overdue,
      missed: missed,
      cancelled: cancelled,
      completedToday: completedToday,
      completedThisWeek: completedThisWeek,
      completedThisMonth: completedThisMonth,
      byPriority: byPriority,
      byCategory: byCategory,
      completedPerDay: completedPerDay,
      chartStart: chartStart,
    );
  }
}
