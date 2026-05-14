import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Derived RTOS task visualization.
///
/// Shows estimated task activity based on telemetry and diagnostics data.
/// The ESP32-S3 runs 8 RTOS tasks — this widget visualizes their inferred
/// activity without fabricating unrealistic metrics.
class RtosVisualization extends StatelessWidget {
  final double fps;
  final int packetRate;
  final int wifiRssi;
  final int heap;
  final bool isConnected;

  const RtosVisualization({
    super.key,
    required this.fps,
    required this.packetRate,
    required this.wifiRssi,
    required this.heap,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    // Derive task activity from diagnostics data.
    final tasks = <_RtosTask>[
      _RtosTask(
        name: 'Game Loop',
        core: 1,
        activity: _gameLoopActivity(),
        color: AppConstants.neonCyan,
        icon: Icons.sports_esports,
      ),
      _RtosTask(
        name: 'Input Handler',
        core: 1,
        activity: _inputActivity(),
        color: AppConstants.neonGreen,
        icon: Icons.touch_app,
      ),
      _RtosTask(
        name: 'LED Renderer',
        core: 1,
        activity: _ledActivity(),
        color: AppConstants.neonMagenta,
        icon: Icons.lightbulb,
      ),
      _RtosTask(
        name: 'WiFi Telemetry',
        core: 0,
        activity: _wifiActivity(),
        color: AppConstants.neonBlue,
        icon: Icons.wifi,
      ),
      _RtosTask(
        name: 'Display (OLED)',
        core: 0,
        activity: _displayActivity(),
        color: AppConstants.neonYellow,
        icon: Icons.tv,
      ),
      _RtosTask(
        name: 'Audio / Buzzer',
        core: 1,
        activity: _audioActivity(),
        color: AppConstants.neonOrange,
        icon: Icons.volume_up,
      ),
      _RtosTask(
        name: 'Watchdog',
        core: 0,
        activity: 0.15, // Watchdog runs minimally
        color: AppConstants.textDim,
        icon: Icons.shield_outlined,
      ),
      _RtosTask(
        name: 'System Idle',
        core: 0,
        activity: _idleActivity(),
        color: const Color(0xFF334155),
        icon: Icons.memory,
      ),
    ];

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
              Icon(Icons.memory, color: AppConstants.neonCyan, size: 16),
              const SizedBox(width: 8),
              Text(
                'RTOS TASKS',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '8 TASKS · 2 CORES',
                style: TextStyle(
                  color: AppConstants.textDim.withValues(alpha: 0.6),
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Task list
          ...tasks.map((t) => _TaskBar(task: t)),
        ],
      ),
    );
  }

  // ─── Activity Derivation (from real telemetry data) ───────────

  double _gameLoopActivity() {
    if (fps <= 0) return 0;
    // Higher FPS = higher CPU usage for game loop
    return (fps / 60.0).clamp(0.1, 1.0) * 0.8;
  }

  double _inputActivity() {
    // Input polling is constant but lightweight
    return fps > 0 ? 0.25 : 0.05;
  }

  double _ledActivity() {
    // LED rendering is proportional to FPS
    if (fps <= 0) return 0;
    return (fps / 60.0).clamp(0.1, 1.0) * 0.6;
  }

  double _wifiActivity() {
    if (!isConnected) return 0.05;
    // Activity proportional to packet rate
    return (packetRate / 20.0).clamp(0.1, 0.9);
  }

  double _displayActivity() {
    // OLED updates at fixed interval, low overhead
    return fps > 0 ? 0.2 : 0.05;
  }

  double _audioActivity() {
    // Audio runs intermittently
    return fps > 0 ? 0.15 : 0.02;
  }

  double _idleActivity() {
    // Inverse of overall load
    final load = _gameLoopActivity() + _wifiActivity() + _ledActivity();
    return (1.0 - load / 3.0).clamp(0.05, 0.8);
  }
}

class _RtosTask {
  final String name;
  final int core;
  final double activity; // 0.0–1.0
  final Color color;
  final IconData icon;

  const _RtosTask({
    required this.name,
    required this.core,
    required this.activity,
    required this.color,
    required this.icon,
  });
}

class _TaskBar extends StatelessWidget {
  final _RtosTask task;
  const _TaskBar({required this.task});

  @override
  Widget build(BuildContext context) {
    final pct = (task.activity * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(task.icon, color: task.color.withValues(alpha: 0.7), size: 14),
          const SizedBox(width: 8),
          SizedBox(
            width: 95,
            child: Text(
              task.name,
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'C${task.core}',
            style: TextStyle(
              color: AppConstants.textDim.withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: task.activity.clamp(0, 1),
                  backgroundColor: task.color.withValues(alpha: 0.08),
                  valueColor:
                      AlwaysStoppedAnimation(task.color.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: task.color.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
