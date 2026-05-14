import 'package:flutter/material.dart';

import '../models/game_event.dart';
import '../utils/constants.dart';

/// Maps [GameEvent] types to icons and colors for the timeline.
///
/// Provides a centralized mapping system for event visual representation.
class EventIcons {
  EventIcons._();

  /// Returns the icon for the given event type.
  static IconData getIcon(String eventType) {
    switch (eventType) {
      case 'BOSS_SPAWNED':
        return Icons.whatshot_rounded;
      case 'BOSS_DEFEATED':
        return Icons.emoji_events_rounded;
      case 'BOSS_SEGMENT_DESTROYED':
        return Icons.broken_image_rounded;
      case 'LEVEL_COMPLETED':
        return Icons.workspace_premium_rounded;
      case 'GAME_OVER':
        return Icons.warning_amber_rounded;
      case 'COMBO_TRIGGERED':
        return Icons.bolt_rounded;
      case 'COMBO_FAILED':
        return Icons.bolt_rounded;
      case 'SIMON_STARTED':
        return Icons.psychology_rounded;
      case 'SIMON_COMPLETED':
        return Icons.psychology_alt_rounded;
      case 'BEAT_SABER_STARTED':
        return Icons.music_note_rounded;
      case 'BEAT_SABER_COMPLETED':
        return Icons.music_off_rounded;
      case 'ENEMY_DESTROYED':
        return Icons.gps_fixed_rounded;
      case 'PLAYER_HIT':
        return Icons.heart_broken_rounded;
      case 'PLAYER_DIED':
        return Icons.dangerous_rounded;
      case 'STATE_CHANGED':
        return Icons.swap_horiz_rounded;
      case 'GAME_WON':
        return Icons.emoji_events_rounded;
      case 'BASE_DESTROYED':
        return Icons.dangerous_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  /// Returns the accent color for the given event type.
  static Color getEventColor(String eventType) {
    switch (eventType) {
      case 'BOSS_SPAWNED':
        return AppConstants.neonRed;
      case 'BOSS_DEFEATED':
        return AppConstants.neonGreen;
      case 'BOSS_SEGMENT_DESTROYED':
        return AppConstants.neonOrange;
      case 'LEVEL_COMPLETED':
        return AppConstants.neonYellow;
      case 'GAME_OVER':
        return AppConstants.neonRed;
      case 'COMBO_TRIGGERED':
        return AppConstants.neonCyan;
      case 'COMBO_FAILED':
        return AppConstants.neonOrange;
      case 'SIMON_STARTED':
      case 'SIMON_COMPLETED':
        return AppConstants.neonMagenta;
      case 'BEAT_SABER_STARTED':
      case 'BEAT_SABER_COMPLETED':
        return AppConstants.neonBlue;
      case 'ENEMY_DESTROYED':
        return AppConstants.neonGreen;
      case 'PLAYER_HIT':
        return AppConstants.neonOrange;
      case 'PLAYER_DIED':
        return AppConstants.neonRed;
      case 'STATE_CHANGED':
        return AppConstants.neonCyan;
      case 'GAME_WON':
        return AppConstants.neonGreen;
      case 'BASE_DESTROYED':
        return AppConstants.neonRed;
      default:
        return AppConstants.textDim;
    }
  }

  /// Returns the severity color.
  static Color getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'error':
        return AppConstants.neonRed;
      case 'warning':
        return AppConstants.neonOrange;
      case 'info':
      default:
        return AppConstants.neonCyan;
    }
  }

  /// Returns the severity icon.
  static IconData getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'error':
        return Icons.error_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'info':
      default:
        return Icons.info_rounded;
    }
  }
}
