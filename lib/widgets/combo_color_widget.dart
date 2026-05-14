import 'package:flutter/material.dart';

import '../utils/color_utils.dart';
import '../utils/constants.dart';

/// Displays the current combo color with visual indicator and mix formula.
class ComboColorWidget extends StatelessWidget {
  final int comboColorId;

  const ComboColorWidget({super.key, required this.comboColorId});

  @override
  Widget build(BuildContext context) {
    final color = ColorUtils.ledColor(comboColorId);
    final name = ColorUtils.ledColorName(comboColorId);
    final desc = ColorUtils.comboDescription(comboColorId);
    final hasCombo = comboColorId >= 4;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: hasCombo ? color.withValues(alpha: 0.3) : AppConstants.borderDim,
        ),
        boxShadow: hasCombo ? ColorUtils.cardGlow(color) : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette, color: AppConstants.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text('COMBO COLOR', style: TextStyle(
                color: AppConstants.textDim, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AnimatedContainer(
                duration: AppConstants.mediumAnim,
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  boxShadow: hasCombo ? ColorUtils.neonGlow(color, intensity: 0.8) : [],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: AppConstants.fastAnim,
                    child: Text(name, key: ValueKey(name), style: TextStyle(
                      color: hasCombo ? color : AppConstants.textSecondary,
                      fontSize: 18, fontWeight: FontWeight.w700,
                    )),
                  ),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(
                    color: AppConstants.textDim, fontSize: 11,
                  )),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
