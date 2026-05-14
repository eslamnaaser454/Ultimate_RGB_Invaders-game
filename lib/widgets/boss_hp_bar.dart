import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import '../utils/constants.dart';

/// Animated boss health bar with gradient color transitions.
class BossHpBar extends StatefulWidget {
  final int currentHP;
  final int maxHP;
  final bool isBossFight;

  const BossHpBar({
    super.key,
    required this.currentHP,
    required this.maxHP,
    this.isBossFight = false,
  });

  @override
  State<BossHpBar> createState() => _BossHpBarState();
}

class _BossHpBarState extends State<BossHpBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _checkPulse();
  }

  @override
  void didUpdateWidget(BossHpBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkPulse();
  }

  void _checkPulse() {
    final ratio = widget.maxHP > 0
        ? (widget.currentHP / widget.maxHP).clamp(0.0, 1.0)
        : 0.0;

    if (ratio > 0 && ratio <= 0.25 && widget.isBossFight) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.maxHP > 0
        ? (widget.currentHP / widget.maxHP).clamp(0.0, 1.0)
        : 0.0;
    final barColor = ColorUtils.hpColor(ratio);

    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: barColor.withValues(alpha: 0.3), width: 1),
        boxShadow: ColorUtils.cardGlow(barColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.favorite, color: barColor, size: 18),
              const SizedBox(width: 8),
              Text('BOSS HP', style: TextStyle(
                color: barColor, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 2,
              )),
              const Spacer(),
              AnimatedBuilder(
                listenable: _pulseController,
                builder: (context, _) {
                  return Text(
                    '${widget.currentHP} / ${widget.maxHP}',
                    style: TextStyle(
                      color: barColor.withValues(
                          alpha: 0.7 + _pulseController.value * 0.3),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // HP Bar
          AnimatedBuilder(
            listenable: _pulseController,
            builder: (context, _) {
              return Container(
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: barColor.withValues(
                        alpha: 0.2 + _pulseController.value * 0.3),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    children: [
                      AnimatedFractionallySizedBox(
                        duration: AppConstants.mediumAnim,
                        curve: Curves.easeOutCubic,
                        widthFactor: ratio,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              barColor.withValues(alpha: 0.8),
                              barColor,
                            ]),
                            boxShadow: [
                              BoxShadow(
                                color: barColor.withValues(
                                    alpha: 0.4 + _pulseController.value * 0.3),
                                blurRadius: 8, spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.15),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 8),

          // Percentage + boss badge
          Row(
            children: [
              Text('${(ratio * 100).toStringAsFixed(0)}%', style: TextStyle(
                color: barColor.withValues(alpha: 0.7),
                fontSize: 12, fontWeight: FontWeight.w600,
              )),
              const Spacer(),
              if (widget.isBossFight)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.neonRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppConstants.neonRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department,
                          color: AppConstants.neonRed, size: 12),
                      const SizedBox(width: 4),
                      Text('BOSS ACTIVE', style: TextStyle(
                        color: AppConstants.neonRed, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 1,
                      )),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Helper widget that rebuilds when an animation notifies listeners.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) => builder(context, child);
}
