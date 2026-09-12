import 'package:flutter/material.dart';

import '../../../../core/utils/task_status_calculator.dart';

/// A small colored chip showing a task's computed display status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TaskDisplayStatus status;

  static const Map<TaskDisplayStatus, Color> _colors = {
    TaskDisplayStatus.pending: Color(0xFF6C757D),
    TaskDisplayStatus.inProgress: Color(0xFF2E86AB),
    TaskDisplayStatus.completed: Color(0xFF06A77D),
    TaskDisplayStatus.overdue: Color(0xFFE63946),
    TaskDisplayStatus.snoozed: Color(0xFFF77F00),
    TaskDisplayStatus.cancelled: Color(0xFF9E9E9E),
  };

  static const Map<TaskDisplayStatus, String> _labels = {
    TaskDisplayStatus.pending: 'Pending',
    TaskDisplayStatus.inProgress: 'In Progress',
    TaskDisplayStatus.completed: 'Completed',
    TaskDisplayStatus.overdue: 'Overdue',
    TaskDisplayStatus.snoozed: 'Snoozed',
    TaskDisplayStatus.cancelled: 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _labels[status]!,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
