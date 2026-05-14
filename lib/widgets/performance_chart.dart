import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A reusable cyberpunk-styled mini chart for performance history data.
///
/// Renders a sparkline with a gradient fill, value labels, and optional
/// threshold lines. Uses [CustomPainter] with [RepaintBoundary] for
/// efficient repainting — only redraws when data actually changes.
///
/// Used for: FPS history, latency, heap usage, packet rate charts.
class PerformanceChart extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final List<double> data;
  final Color lineColor;
  final double? minY;
  final double? maxY;
  final double? warningThreshold;
  final bool invertWarning;

  const PerformanceChart({
    super.key,
    required this.label,
    required this.value,
    required this.data,
    required this.lineColor,
    this.unit,
    this.minY,
    this.maxY,
    this.warningThreshold,
    this.invertWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConstants.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                unit != null ? '$value $unit' : value,
                style: TextStyle(
                  color: lineColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Chart area
          RepaintBoundary(
            child: SizedBox(
              height: 48,
              child: data.length < 2
                  ? Center(
                      child: Text(
                        'Collecting data…',
                        style: TextStyle(
                          color: AppConstants.textDim,
                          fontSize: 10,
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: _SparklinePainter(
                        data: data,
                        lineColor: lineColor,
                        minY: minY,
                        maxY: maxY,
                        warningThreshold: warningThreshold,
                        invertWarning: invertWarning,
                      ),
                      size: const Size(double.infinity, 48),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final double? minY;
  final double? maxY;
  final double? warningThreshold;
  final bool invertWarning;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    this.minY,
    this.maxY,
    this.warningThreshold,
    this.invertWarning = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final dataMin = minY ?? data.reduce(math.min);
    final dataMax = maxY ?? data.reduce(math.max);
    final range = (dataMax - dataMin).abs();
    final effectiveRange = range < 0.001 ? 1.0 : range;

    final stepX = size.width / (data.length - 1);

    // Build path
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalized = ((data[i] - dataMin) / effectiveRange).clamp(0.0, 1.0);
      final y = size.height - (normalized * size.height * 0.9) - size.height * 0.05;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Fill
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.15),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Warning threshold line
    if (warningThreshold != null) {
      final threshNorm =
          ((warningThreshold! - dataMin) / effectiveRange).clamp(0.0, 1.0);
      final threshY =
          size.height - (threshNorm * size.height * 0.9) - size.height * 0.05;
      final threshPaint = Paint()
        ..color = AppConstants.neonRed.withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, threshY),
        Offset(size.width, threshY),
        threshPaint,
      );
    }

    // Line stroke
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) {
    return old.data.length != data.length ||
        (data.isNotEmpty && old.data.isNotEmpty && old.data.last != data.last);
  }
}
