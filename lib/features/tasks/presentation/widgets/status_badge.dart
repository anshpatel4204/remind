import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/task_status_calculator.dart';

/// A small colored chip showing a task's computed display status. Colors/
/// labels come from [AppColors], matching [PriorityBadge]'s pattern.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TaskDisplayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.status[status]!;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        AppColors.statusLabel[status]!,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
