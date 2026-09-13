import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// The shared "something went wrong" panel for a failed `FutureBuilder`,
/// with a Retry action. Every screen that loads data from the repositories
/// (Home, Tasks, Calendar, Statistics, Task details) shows this same panel
/// on error instead of five slightly different hand-rolled ones.
class REmindErrorState extends StatelessWidget {
  const REmindErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
