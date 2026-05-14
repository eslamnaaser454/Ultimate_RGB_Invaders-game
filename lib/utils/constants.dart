import 'package:flutter/material.dart';

/// App-wide design constants for the cyberpunk dashboard theme.
class AppConstants {
  AppConstants._();

  // ─── Brand Colors ───────────────────────────────────────────────
  static const Color neonCyan = Color(0xFF00FFFF);
  static const Color neonMagenta = Color(0xFFFF00FF);
  static const Color neonBlue = Color(0xFF4D7CFF);
  static const Color neonGreen = Color(0xFF39FF14);
  static const Color neonYellow = Color(0xFFFFFF00);
  static const Color neonRed = Color(0xFFFF003C);
  static const Color neonOrange = Color(0xFFFF6600);

  // ─── Surface Colors ────────────────────────────────────────────
  static const Color bgPrimary = Color(0xFF0A0E17);
  static const Color bgCard = Color(0xFF111827);
  static const Color bgCardLight = Color(0xFF1A2332);
  static const Color bgSurface = Color(0xFF0D1321);
  static const Color borderDim = Color(0xFF1E293B);
  static const Color borderGlow = Color(0xFF334155);

  // ─── Text Colors ───────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDim = Color(0xFF64748B);

  // ─── LED Color Map ─────────────────────────────────────────────
  /// Maps LED color ID from ESP32 JSON to Flutter Color.
  static const Map<int, Color> ledColors = {
    0: Color(0xFF111111), // Off (dim dark, not pure black for visibility)
    1: Color(0xFF0066FF), // Blue
    2: Color(0xFFFF0033), // Red
    3: Color(0xFF00FF41), // Green
    4: Color(0xFFFFFF00), // Yellow
    5: Color(0xFFFF00FF), // Magenta
    6: Color(0xFF00FFFF), // Cyan
    7: Color(0xFFFFFFFF), // White
  };

  /// Human-readable LED color names.
  static const Map<int, String> ledColorNames = {
    0: 'Off',
    1: 'Blue',
    2: 'Red',
    3: 'Green',
    4: 'Yellow',
    5: 'Magenta',
    6: 'Cyan',
    7: 'White',
  };

  // ─── Game States ───────────────────────────────────────────────
  static const Map<String, String> gameStateLabels = {
    'IDLE': 'Idle',
    'PLAYING': 'Playing',
    'BOSS': 'Boss Fight',
    'WAVE': 'Enemy Wave',
    'GAMEOVER': 'Game Over',
    'WIN': 'Victory',
    'PAUSED': 'Paused',
    'MENU': 'Main Menu',
    'BONUS': 'Bonus Round',
    'TRANSITION': 'Level Transition',
  };

  static const Map<String, String> gameModeLabels = {
    'NORMAL': 'Normal',
    'FINAL_BOSS': 'Final Boss',
    'SIMON_SAYS': 'Simon Says',
    'BEAT_SABER': 'Beat Saber',
    'SURVIVAL': 'Survival',
  };

  // ─── Layout ────────────────────────────────────────────────────
  static const double cardRadius = 16.0;
  static const double cardPadding = 16.0;
  static const double gridSpacing = 12.0;
  static const double screenPadding = 16.0;
  static const double ledSize = 18.0;
  static const double ledSpacing = 3.0;

  // ─── LED Strip Painter ─────────────────────────────────────────
  static const double ledPainterWidth = 14.0;
  static const double ledPainterHeight = 22.0;
  static const double ledPainterSpacing = 3.0;
  static const double ledPainterRowGap = 8.0;
  static const double ledPainterRadius = 3.0;

  // ─── Bottom Navigation ─────────────────────────────────────────
  static const double bottomNavHeight = 68.0;
  static const Color bottomNavBg = Color(0xFF080C14);
  static const Color bottomNavBorder = Color(0xFF1A2332);

  // ─── Debug Overlay ─────────────────────────────────────────────
  static const Color overlayBg = Color(0xCC0A0E17);

  // ─── Animation Durations ───────────────────────────────────────
  static const Duration fastAnim = Duration(milliseconds: 200);
  static const Duration mediumAnim = Duration(milliseconds: 400);
  static const Duration slowAnim = Duration(milliseconds: 800);

  // ─── Performance ──────────────────────────────────────────────
  static const int maxEventBuffer = 200;
  static const int perfSampleIntervalMs = 500;
}
