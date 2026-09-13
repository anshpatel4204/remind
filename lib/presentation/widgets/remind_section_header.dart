import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A small, consistent heading for a section within a screen (e.g. "Pinned",
/// "Today's tasks", "By priority") - an optional leading icon, the title,
/// and an optional trailing widget (e.g. a "See all" action).
class REmindSectionHeader extends StatelessWidget {
  const REmindSectionHeader(
      {super.key, required this.title, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon,
              size: AppSpacing.iconSmall + 2,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs + 2),
        ],
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (trailing != null) trailing!,
      ],
    );
  }
}
