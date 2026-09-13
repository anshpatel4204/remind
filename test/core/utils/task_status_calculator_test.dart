import 'package:flutter_test/flutter_test.dart';

import 'package:remind/core/utils/task_status_calculator.dart';
import 'package:remind/data/models/enums.dart';
import 'package:remind/data/models/task_model.dart';

void main() {
  final now = DateTime(2026, 6, 15, 12, 0);
  final past = DateTime(2026, 6, 10, 9, 0);
  final future = DateTime(2026, 6, 20, 9, 0);

  TaskModel taskWith({
    TaskStatus status = TaskStatus.pending,
    DateTime? dueDate,
  }) {
    return TaskModel(
      title: 'Test task',
      status: status,
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('TaskStatusCalculator.displayStatusFor', () {
    test('a pending task past its due date is Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.pending, dueDate: past),
        now: now,
      );
      expect(status, TaskDisplayStatus.overdue);
    });

    test('an in-progress task past its due date is Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.inProgress, dueDate: past),
        now: now,
      );
      expect(status, TaskDisplayStatus.overdue);
    });

    test('a pending task due in the future is Pending', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.pending, dueDate: future),
        now: now,
      );
      expect(status, TaskDisplayStatus.pending);
    });

    test('an in-progress task due in the future is In Progress', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.inProgress, dueDate: future),
        now: now,
      );
      expect(status, TaskDisplayStatus.inProgress);
    });

    test('a task with no due date is never Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.pending, dueDate: null),
        now: now,
      );
      expect(status, TaskDisplayStatus.pending);
    });

    test('a completed task is Completed even if its due date is in the past',
        () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.completed, dueDate: past),
        now: now,
      );
      expect(status, TaskDisplayStatus.completed);
    });

    test('a cancelled task is Cancelled even if its due date is in the past',
        () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.cancelled, dueDate: past),
        now: now,
      );
      expect(status, TaskDisplayStatus.cancelled);
    });

    test('an active snooze shows Snoozed instead of Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.pending, dueDate: past),
        now: now,
        hasActiveSnooze: true,
      );
      expect(status, TaskDisplayStatus.snoozed);
    });

    test('a completed task is Completed even with an active snooze flag', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.completed, dueDate: past),
        now: now,
        hasActiveSnooze: true,
      );
      expect(status, TaskDisplayStatus.completed);
    });

    test('a due date exactly at "now" is not yet Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(status: TaskStatus.pending, dueDate: now),
        now: now,
      );
      expect(status, TaskDisplayStatus.pending);
    });

    test('a due date one minute in the past is Overdue', () {
      final status = TaskStatusCalculator.displayStatusFor(
        taskWith(
            status: TaskStatus.pending,
            dueDate: now.subtract(const Duration(minutes: 1))),
        now: now,
      );
      expect(status, TaskDisplayStatus.overdue);
    });
  });
}
