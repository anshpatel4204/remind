import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/utils/statistics_calculator.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/models/task_model.dart';

void main() {
  // Monday, so weekStart below lands on `now` itself and every test's
  // week/month boundaries are unambiguous.
  final now = DateTime(2026, 6, 15, 12, 0);

  TaskModel taskWith({
    TaskStatus status = TaskStatus.pending,
    DateTime? dueDate,
    DateTime? completedAt,
    TaskPriority priority = TaskPriority.medium,
    int? categoryId,
  }) {
    return TaskModel(
      title: 'Test task',
      status: status,
      dueDate: dueDate,
      completedAt: completedAt,
      priority: priority,
      categoryId: categoryId,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('StatisticsCalculator.compute - basic counts', () {
    test('an empty task list gives all-zero stats and a 0 completion rate', () {
      final stats = StatisticsCalculator.compute([], now: now);
      expect(stats.total, 0);
      expect(stats.completed, 0);
      expect(stats.pending, 0);
      expect(stats.overdue, 0);
      expect(stats.missed, 0);
      expect(stats.cancelled, 0);
      expect(stats.completionRate, 0);
      expect(stats.completedPerDay, List<int>.filled(7, 0));
    });

    test('a pending task due in the future counts as pending, not overdue', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(dueDate: now.add(const Duration(days: 1)))],
        now: now,
      );
      expect(stats.pending, 1);
      expect(stats.overdue, 0);
    });

    test('a pending task past its due date counts as overdue', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(dueDate: now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(stats.overdue, 1);
      expect(stats.pending, 0);
    });

    test('an in-progress task past its due date also counts as overdue', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.inProgress, dueDate: now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(stats.overdue, 1);
    });

    test('completionRate is completed divided by total', () {
      final stats = StatisticsCalculator.compute(
        [
          taskWith(status: TaskStatus.completed, completedAt: now),
          taskWith(),
          taskWith(),
        ],
        now: now,
      );
      expect(stats.total, 3);
      expect(stats.completed, 1);
      expect(stats.completionRate, closeTo(1 / 3, 0.0001));
    });
  });

  group('StatisticsCalculator.compute - overdue vs missed', () {
    test('a cancelled task whose due date already passed counts as missed', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.cancelled, dueDate: now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(stats.cancelled, 1);
      expect(stats.missed, 1);
      expect(stats.overdue, 0);
    });

    test('a cancelled task with no due date is not counted as missed', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.cancelled)],
        now: now,
      );
      expect(stats.cancelled, 1);
      expect(stats.missed, 0);
    });

    test('a cancelled task due in the future is not counted as missed', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.cancelled, dueDate: now.add(const Duration(days: 1)))],
        now: now,
      );
      expect(stats.cancelled, 1);
      expect(stats.missed, 0);
    });
  });

  group('StatisticsCalculator.compute - completed today/this week/this month', () {
    test('a task completed today counts in all three windows and in "today"\'s chart bar', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.completed, completedAt: now)],
        now: now,
      );
      expect(stats.completedToday, 1);
      expect(stats.completedThisWeek, 1);
      expect(stats.completedThisMonth, 1);
      expect(stats.completedPerDay.last, 1);
    });

    test('a task completed yesterday (last week, same month) only counts this month', () {
      // `now` is a Monday, so yesterday falls in the previous calendar week.
      final yesterday = now.subtract(const Duration(days: 1));
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.completed, completedAt: yesterday)],
        now: now,
      );
      expect(stats.completedToday, 0);
      expect(stats.completedThisWeek, 0);
      expect(stats.completedThisMonth, 1);
    });

    test('a task completed before this month started counts in none of the three', () {
      final lastMonth = DateTime(now.year, now.month - 1, 20);
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.completed, completedAt: lastMonth)],
        now: now,
      );
      expect(stats.completedToday, 0);
      expect(stats.completedThisWeek, 0);
      expect(stats.completedThisMonth, 0);
    });

    test('a task completed 5 days ago lands in the correct chart bar', () {
      final fiveDaysAgo = now.subtract(const Duration(days: 5));
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.completed, completedAt: fiveDaysAgo)],
        now: now,
      );
      // chartStart is 6 days before today, so 5 days ago is the 2nd bar.
      expect(stats.completedPerDay[1], 1);
      expect(stats.completedPerDay.reduce((a, b) => a + b), 1);
    });

    test('a task completed more than 6 days ago does not appear in the chart at all', () {
      final longAgo = now.subtract(const Duration(days: 30));
      final stats = StatisticsCalculator.compute(
        [taskWith(status: TaskStatus.completed, completedAt: longAgo)],
        now: now,
      );
      expect(stats.completedPerDay, List<int>.filled(7, 0));
      // ...but it's still counted as completed overall.
      expect(stats.completed, 1);
    });
  });

  group('StatisticsCalculator.compute - breakdowns', () {
    test('byPriority tallies every task, including priorities with zero tasks', () {
      final stats = StatisticsCalculator.compute(
        [
          taskWith(priority: TaskPriority.high),
          taskWith(priority: TaskPriority.high),
          taskWith(priority: TaskPriority.low),
        ],
        now: now,
      );
      expect(stats.byPriority[TaskPriority.high], 2);
      expect(stats.byPriority[TaskPriority.low], 1);
      expect(stats.byPriority[TaskPriority.medium], 0);
      expect(stats.byPriority[TaskPriority.urgent], 0);
    });

    test('byCategory groups uncategorized tasks under a null key', () {
      final stats = StatisticsCalculator.compute(
        [taskWith(categoryId: 1), taskWith(categoryId: 1), taskWith()],
        now: now,
      );
      expect(stats.byCategory[1], 2);
      expect(stats.byCategory[null], 1);
    });

    test('sortedCategoryCounts orders categories from most to least tasks', () {
      final stats = StatisticsCalculator.compute(
        [
          taskWith(categoryId: 1),
          taskWith(categoryId: 2),
          taskWith(categoryId: 2),
          taskWith(categoryId: 2),
        ],
        now: now,
      );
      final sorted = stats.sortedCategoryCounts();
      expect(sorted.first.key, 2);
      expect(sorted.first.value, 3);
      expect(sorted.last.key, 1);
    });
  });
}
