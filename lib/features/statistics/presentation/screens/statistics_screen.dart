import 'package:flutter/material.dart';

import '../../../../presentation/widgets/placeholder_view.dart';

/// Placeholder Statistics screen — no charts/data implemented yet.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Statistics',
      icon: Icons.bar_chart_outlined,
    );
  }
}
