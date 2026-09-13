import 'package:flutter/material.dart';

/// One bar in a [REmindBarChart].
class BarValue {
  const BarValue({required this.label, required this.value});

  final String label;
  final int value;
}

/// A simple vertical bar chart (e.g. tasks completed per weekday) - built
/// out of plain [Container]s so it needs no charting package dependency,
/// matching Statistics' existing "no new dependency" approach.
class REmindBarChart extends StatelessWidget {
  const REmindBarChart({super.key, required this.values, this.height = 120});

  final List<BarValue> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (m, v) => v.value > m ? v.value : m);
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (bar.value > 0)
                      Text(
                        '${bar.value}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    const SizedBox(height: 4),
                    Container(
                      height: maxValue == 0
                          ? 4
                          : (height - 44) *
                              (bar.value / maxValue).clamp(0.04, 1.0),
                      decoration: BoxDecoration(
                        color: bar.value == 0
                            ? color.withValues(alpha: 0.15)
                            : color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
