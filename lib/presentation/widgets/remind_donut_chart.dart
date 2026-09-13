import 'package:flutter/material.dart';

/// One slice of a [REmindDonutChart].
class DonutSegment {
  const DonutSegment(
      {required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;
}

/// A simple ring/donut chart with a centered total - used by Statistics'
/// "Category Breakdown" to match the reference without pulling in a
/// charting package dependency. Pure [CustomPainter], no external deps.
class REmindDonutChart extends StatelessWidget {
  const REmindDonutChart({
    super.key,
    required this.segments,
    required this.centerLabel,
    this.size = 140,
    this.strokeWidth = 20,
  });

  final List<DonutSegment> segments;
  final String centerLabel;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, s) => sum + s.value);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(
              segments: segments,
              total: total,
              strokeWidth: strokeWidth,
              trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerLabel, style: Theme.of(context).textTheme.titleLarge),
              Text('Tasks', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
    required this.trackColor,
  });

  final List<DonutSegment> segments;
  final int total;
  final double strokeWidth;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, 6.2832, false, trackPaint);

    if (total <= 0) return;

    var startAngle = -1.5708; // -90 degrees, 12 o'clock
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = (segment.value / total) * 6.2832;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(arcRect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.segments != segments || oldDelegate.total != total;
  }
}
