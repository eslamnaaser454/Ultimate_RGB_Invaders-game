import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import '../utils/constants.dart';

/// Animated badge showing the current game state or mode.
class GameStateBadge extends StatelessWidget {
  final String state;
  final String mode;

  const GameStateBadge({super.key, required this.state, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppConstants.borderDim, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videogame_asset, color: AppConstants.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text('GAME STATUS', style: TextStyle(
                color: AppConstants.textDim, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Badge(
                label: 'STATE',
                value: AppConstants.gameStateLabels[state.toUpperCase()] ?? state,
                color: ColorUtils.stateColor(state),
              ),
              const SizedBox(width: 10),
              _Badge(
                label: 'MODE',
                value: AppConstants.gameModeLabels[mode.toUpperCase()] ?? mode,
                color: ColorUtils.modeColor(mode),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Badge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: AppConstants.mediumAnim,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(
              color: color.withValues(alpha: 0.6), fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 1.5,
            )),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: AppConstants.fastAnim,
              child: Text(value, key: ValueKey(value), style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w700,
              )),
            ),
          ],
        ),
      ),
    );
  }
}
