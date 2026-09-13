import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A single at-a-glance stat tile (an icon in a colored badge, a count, a
/// label) - the shared shape behind Home's Overdue/Due Today/Upcoming/
/// Completed cards and Statistics' Total/Completed/Pending/Overdue cards,
/// so both screens present numbers identically instead of two
/// almost-but-not-quite-matching card styles.
class REmindStatCard extends StatelessWidget {
  const REmindStatCard({
    super.key,
    this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.sm + 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
              ],
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
