import 'dart:math';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Circular gauge widget for displaying accuracy percentage.
class AccuracyGauge extends StatelessWidget {
  final int accuracy;

  const AccuracyGauge({super.key, required this.accuracy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppConstants.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, color: AppConstants.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text('ACCURACY', style: TextStyle(
                color: AppConstants.textDim, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 100, height: 100,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: accuracy.toDouble()),
                duration: AppConstants.mediumAnim,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return CustomPaint(
                    painter: _GaugePainter(value / 100),
                    child: Center(
                      child: Text(
                        '${value.toInt()}%',
                        style: TextStyle(
                          color: _gaugeColor(value / 100),
                          fontSize: 22, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _gaugeColor(double ratio) {
    if (ratio >= 0.8) return AppConstants.neonGreen;
    if (ratio >= 0.5) return AppConstants.neonYellow;
    return AppConstants.neonRed;
  }
}

class _GaugePainter extends CustomPainter {
  final double ratio;
  _GaugePainter(this.ratio);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;
    const startAngle = 2.3;
    const sweepTotal = 2 * pi - 1.0;

    // Background arc
    final bgPaint = Paint()
      ..color = const Color(0xFF1A2332)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal, false, bgPaint,
    );

    // Foreground arc
    Color color;
    if (ratio >= 0.8) {
      color = AppConstants.neonGreen;
    } else if (ratio >= 0.5) {
      color = AppConstants.neonYellow;
    } else {
      color = AppConstants.neonRed;
    }

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal * ratio.clamp(0, 1), false, fgPaint,
    );

    // Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal * ratio.clamp(0, 1), false, glowPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.ratio != ratio;
}
