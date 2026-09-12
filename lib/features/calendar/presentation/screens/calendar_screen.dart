import 'package:flutter/material.dart';

import '../../../../presentation/widgets/placeholder_view.dart';

/// Placeholder Calendar screen — no calendar functionality implemented yet.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Calendar',
      icon: Icons.calendar_today_outlined,
    );
  }
}
