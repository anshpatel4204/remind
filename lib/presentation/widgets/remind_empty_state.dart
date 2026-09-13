import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// REmind's shared "nothing here" panel - an icon (or brand image),
/// title, optional message, and optional primary action. Every empty
/// state in the app (no tasks yet, no tasks today, no tasks matching a
/// filter, nothing due on a selected calendar day, no data for
/// statistics) renders through this one widget so they share the same
/// spacing, typography, and tone instead of each screen inventing its own.
///
/// [compact] renders as a [Card] with tighter padding - used for an
/// empty state that sits inline within a list (e.g. "No tasks for today"
/// under Home's stat cards) rather than filling the whole screen.
class REmindEmptyState extends StatelessWidget {
  const REmindEmptyState({
    super.key,
    this.icon,
    this.imageAsset,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData? icon;
  final String? imageAsset;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageAsset != null)
          Image.asset(imageAsset!, width: 96, height: 96)
        else if (icon != null)
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        if (imageAsset != null || icon != null)
          const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: AppSpacing.xl),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );

    final padded = Padding(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
      child: content,
    );

    return compact ? Card(child: padded) : Center(child: padded);
  }
}
