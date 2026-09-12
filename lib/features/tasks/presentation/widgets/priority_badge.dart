import 'package:flutter/material.dart';

import '../../../../data/models/enums.dart';

/// A small colored chip showing a task's priority.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final TaskPriority priority;

  static const Map<TaskPriority, Color> _colors = {
    TaskPriority.low: Color(0xFF6C757D),
    TaskPriority.medium: Color(0xFF2E86AB),
    TaskPriority.high: Color(0xFFF77F00),
    TaskPriority.urgent: Color(0xFFE63946),
  };

  static const Map<TaskPriority, String> _labels = {
    TaskPriority.low: 'Low',
    TaskPriority.medium: 'Medium',
    TaskPriority.high: 'High',
    TaskPriority.urgent: 'Urgent',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[priority]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _labels[priority]!,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
