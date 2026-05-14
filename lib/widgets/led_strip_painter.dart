import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import '../utils/constants.dart';

/// ⭐ MOST IMPORTANT WIDGET — Phase 1 CustomPainter rewrite ⭐
///
/// High-performance LED strip renderer using [CustomPainter].
/// Renders the entire ESP32 LED strip in a single paint pass with
/// neon glow effects, multi-row wrapping, and cyberpunk aesthetics.
///
/// Performance:
/// - Wrapped in [RepaintBoundary] to isolate repaints
/// - [shouldRepaint] uses deep list comparison
/// - Single paint pass for all LEDs (no widget-per-LED overhead)
/// - Supports 100+ LEDs at 60fps
class LedStripPainterWidget extends StatelessWidget {
  final List<int> leds;

  const LedStripPainterWidget({super.key, required this.leds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: AppConstants.neonCyan.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: ColorUtils.cardGlow(AppConstants.neonCyan),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.light_mode, color: AppConstants.neonCyan, size: 18),
              const SizedBox(width: 8),
              Text(
                'LIVE LED STRIP',
                style: TextStyle(
                  color: AppConstants.neonCyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.neonCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${leds.length} LEDs',
                  style: TextStyle(
                    color: AppConstants.neonCyan.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // LED Strip Canvas
          if (leds.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Awaiting LED data...',
                  style: TextStyle(
                    color: AppConstants.textDim,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = _calcHeight(width, leds.length);
                  return CustomPaint(
                    painter: _LedStripPainter(leds: leds),
                    size: Size(width, height),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Calculates total strip height based on available width and LED count.
  static double _calcHeight(double availableWidth, int ledCount) {
    if (ledCount == 0) return 0;
    const lw = AppConstants.ledPainterWidth;
    const sp = AppConstants.ledPainterSpacing;
    const lh = AppConstants.ledPainterHeight;
    const rg = AppConstants.ledPainterRowGap;
    final perRow = ((availableWidth + sp) / (lw + sp)).floor().clamp(1, 9999);
    final rows = (ledCount / perRow).ceil();
    return rows * lh + (rows - 1) * rg;
  }
}

/// Single-pass CustomPainter for the LED strip.
///
/// Draws all LEDs as rounded rectangles with neon glow, laid out
/// in a multi-row grid that wraps based on available canvas width.
class _LedStripPainter extends CustomPainter {
  final List<int> leds;

  _LedStripPainter({required this.leds});

  static const double _lw = AppConstants.ledPainterWidth;
  static const double _lh = AppConstants.ledPainterHeight;
  static const double _sp = AppConstants.ledPainterSpacing;
  static const double _rg = AppConstants.ledPainterRowGap;
  static const double _r = AppConstants.ledPainterRadius;

  // Pre-allocated reusable paints (avoid GC per frame)
  static final Paint _offPaint = Paint()..color = const Color(0xFF0A0A0A);
  static final Paint _offBorderPaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  static final Paint _glowPaint = Paint();
  static final Paint _fillPaint = Paint();
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  static final Paint _highlightPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (leds.isEmpty) return;

    final perRow = ((size.width + _sp) / (_lw + _sp)).floor().clamp(1, 9999);

    for (int i = 0; i < leds.length; i++) {
      final col = i % perRow;
      final row = i ~/ perRow;
      final x = col * (_lw + _sp);
      final y = row * (_lh + _rg);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, _lw, _lh),
        const Radius.circular(_r),
      );

      final colorId = leds[i];

      if (colorId != 0) {
        final color = ColorUtils.ledColor(colorId);

        // Soft glow layer — solid fill, no blur (mobile-friendly)
        _glowPaint.color = color.withValues(alpha: 0.25);
        final glowRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, y - 2, _lw + 4, _lh + 4),
          const Radius.circular(_r + 2),
        );
        canvas.drawRRect(glowRect, _glowPaint);

        // Solid LED fill
        _fillPaint.color = color.withValues(alpha: 0.9);
        canvas.drawRRect(rect, _fillPaint);

        // Top highlight (specular reflection)
        _highlightPaint.color = Colors.white.withValues(alpha: 0.18);
        final highlightRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, y + 1, _lw - 4, _lh * 0.35),
          const Radius.circular(_r),
        );
        canvas.drawRRect(highlightRect, _highlightPaint);

        // Color border
        _borderPaint.color = color.withValues(alpha: 0.5);
        canvas.drawRRect(rect, _borderPaint);
      } else {
        // Off LED
        canvas.drawRRect(rect, _offPaint);
        canvas.drawRRect(rect, _offBorderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_LedStripPainter oldDelegate) {
    return !listEquals(oldDelegate.leds, leds);
  }
}
