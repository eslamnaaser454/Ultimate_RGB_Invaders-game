import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import '../utils/constants.dart';

/// ⭐ MOST IMPORTANT WIDGET ⭐
///
/// Renders the entire ESP32 LED strip as a real-time animated visual strip.
/// Each LED appears as a glowing colored block that smoothly transitions
/// between colors as new telemetry arrives.
class LedStripWidget extends StatelessWidget {
  final List<int> leds;

  const LedStripWidget({super.key, required this.leds});

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

          // LED Strip
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
            _buildLedStrip(),
        ],
      ),
    );
  }

  Widget _buildLedStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final ledCount = leds.length;
        if (ledCount == 0) return const SizedBox.shrink();

        // Calculate LED size to fit the strip width
        final spacing = 2.0;
        final availableWidth = totalWidth - (spacing * (ledCount - 1));
        final ledWidth = (availableWidth / ledCount).clamp(8.0, 28.0);
        final ledHeight = ledWidth * 1.6;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(leds.length, (i) {
              return _AnimatedLed(
                colorId: leds[i],
                width: ledWidth,
                height: ledHeight,
                index: i,
              );
            }),
          ),
        );
      },
    );
  }
}

/// A single animated LED block with smooth color transitions and glow.
class _AnimatedLed extends StatelessWidget {
  final int colorId;
  final double width;
  final double height;
  final int index;

  const _AnimatedLed({
    required this.colorId,
    required this.width,
    required this.height,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final color = ColorUtils.ledColor(colorId);
    final isOn = colorId != 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: AnimatedContainer(
        duration: AppConstants.fastAnim,
        curve: Curves.easeOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isOn ? color.withValues(alpha: 0.9) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isOn
                ? color.withValues(alpha: 0.6)
                : const Color(0xFF1A1A1A),
            width: 0.5,
          ),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.7),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
      ),
    );
  }
}
