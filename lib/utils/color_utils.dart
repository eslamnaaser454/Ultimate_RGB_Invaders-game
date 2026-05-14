import 'package:flutter/material.dart';
import 'constants.dart';

/// Utility methods for LED colors, glows, and gradients.
class ColorUtils {
  ColorUtils._();

  /// Resolves an LED color ID (0–7) to a Flutter [Color].
  static Color ledColor(int id) {
    return AppConstants.ledColors[id] ?? AppConstants.ledColors[0]!;
  }

  /// Returns a name for the LED color ID.
  static String ledColorName(int id) {
    return AppConstants.ledColorNames[id] ?? 'Unknown';
  }

  /// Builds a neon glow [BoxShadow] list for a given color.
  static List<BoxShadow> neonGlow(Color color, {double intensity = 1.0}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.6 * intensity),
        blurRadius: 8 * intensity,
        spreadRadius: 1 * intensity,
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.3 * intensity),
        blurRadius: 20 * intensity,
        spreadRadius: 2 * intensity,
      ),
    ];
  }

  /// Builds a subtle card border glow.
  static List<BoxShadow> cardGlow(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.15),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ];
  }

  /// Returns a color for the boss HP ratio (1.0 = full green, 0.0 = red).
  static Color hpColor(double ratio) {
    if (ratio > 0.6) return AppConstants.neonGreen;
    if (ratio > 0.3) return AppConstants.neonYellow;
    return AppConstants.neonRed;
  }

  /// Returns a color for the current game state.
  static Color stateColor(String state) {
    switch (state.toUpperCase()) {
      case 'BOSS':
        return AppConstants.neonRed;
      case 'PLAYING':
      case 'WAVE':
        return AppConstants.neonGreen;
      case 'WIN':
        return AppConstants.neonYellow;
      case 'GAMEOVER':
        return AppConstants.neonRed;
      case 'BONUS':
        return AppConstants.neonMagenta;
      case 'PAUSED':
        return AppConstants.neonOrange;
      default:
        return AppConstants.neonCyan;
    }
  }

  /// Returns a color for the game mode.
  static Color modeColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'FINAL_BOSS':
        return AppConstants.neonRed;
      case 'SIMON_SAYS':
        return AppConstants.neonMagenta;
      case 'BEAT_SABER':
        return AppConstants.neonCyan;
      case 'SURVIVAL':
        return AppConstants.neonOrange;
      default:
        return AppConstants.neonBlue;
    }
  }

  /// Combo color description from ID.
  static String comboDescription(int comboId) {
    switch (comboId) {
      case 4:
        return 'Red + Green = Yellow';
      case 5:
        return 'Red + Blue = Magenta';
      case 6:
        return 'Green + Blue = Cyan';
      case 7:
        return 'R + G + B = White';
      default:
        return 'No Combo';
    }
  }
}
