import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/diagnostics_provider.dart';
import '../providers/telemetry_provider.dart';
import '../services/websocket_service.dart' as ws;
import '../utils/constants.dart';
import '../widgets/bug_alert_card.dart';
import '../widgets/performance_chart.dart';
import '../widgets/rtos_visualization.dart';

/// Phase 3 Diagnostics Screen — embedded diagnostics platform.
///
/// Sections:
/// 1. Connection Diagnostics
/// 2. Performance Metrics (FPS, latency, heap, packet rate charts)
/// 3. Bug Detection Panel
/// 4. RTOS Task Visualization
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<DiagnosticsProvider>(
                builder: (context, diagProv, _) {
                  final telProv = context.read<TelemetryProvider>();
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      const SizedBox(height: 4),
                      _ConnectionSection(telProv: telProv, diagProv: diagProv),
                      const SizedBox(height: 12),
                      _PerformanceSection(diagProv: diagProv),
                      const SizedBox(height: 12),
                      _BugDetectionSection(diagProv: diagProv),
                      const SizedBox(height: 12),
                      _RtosSection(diagProv: diagProv, telProv: telProv),
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(Icons.analytics_rounded,
              color: AppConstants.neonCyan, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DIAGNOSTICS',
                style: TextStyle(
                  color: AppConstants.neonCyan,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'SYSTEM MONITOR',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Bug alert badge
          Consumer<DiagnosticsProvider>(
            builder: (_, dp, __) {
              if (!dp.hasCriticalAlerts) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.neonRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppConstants.neonRed.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error, color: AppConstants.neonRed, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${dp.criticalCount}',
                      style: TextStyle(
                        color: AppConstants.neonRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SECTION 1: Connection Diagnostics
// ═══════════════════════════════════════════════════════════════════

class _ConnectionSection extends StatelessWidget {
  final TelemetryProvider telProv;
  final DiagnosticsProvider diagProv;

  const _ConnectionSection({required this.telProv, required this.diagProv});

  @override
  Widget build(BuildContext context) {
    return _SectionContainer(
      title: 'CONNECTION',
      icon: Icons.wifi,
      child: Column(
        children: [
          // Status row
          Row(
            children: [
              _StatusDot(
                  connected:
                      telProv.connectionState == ws.ConnectionState.connected),
              const SizedBox(width: 8),
              Text(
                telProv.isConnected ? 'CONNECTED' : 'DISCONNECTED',
                style: TextStyle(
                  color: telProv.isConnected
                      ? AppConstants.neonGreen
                      : AppConstants.neonRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (telProv.ipAddress.isNotEmpty)
                Text(
                  '${telProv.ipAddress}:${telProv.port}',
                  style: TextStyle(
                    color: AppConstants.textDim,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Metrics grid
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'LATENCY',
                  value: '${diagProv.latency.toStringAsFixed(0)}ms',
                  color: diagProv.latency > 50
                      ? AppConstants.neonRed
                      : diagProv.latency > 20
                          ? AppConstants.neonYellow
                          : AppConstants.neonGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'RSSI',
                  value: '${diagProv.wifiRssi} dBm',
                  color: diagProv.wifiRssi >= -60
                      ? AppConstants.neonGreen
                      : diagProv.wifiRssi >= -75
                          ? AppConstants.neonYellow
                          : AppConstants.neonRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'RECONNECTS',
                  value: '${telProv.reconnectCount}',
                  color: telProv.reconnectCount > 0
                      ? AppConstants.neonOrange
                      : AppConstants.textDim,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'PKT ERRORS',
                  value: '${telProv.packetErrors}',
                  color: telProv.packetErrors > 0
                      ? AppConstants.neonRed
                      : AppConstants.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'HEALTH',
                  value: '${diagProv.telemetryHealth}%',
                  color: diagProv.telemetryHealth >= 95
                      ? AppConstants.neonGreen
                      : diagProv.telemetryHealth >= 80
                          ? AppConstants.neonYellow
                          : AppConstants.neonRed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  label: 'PACKETS',
                  value: '${telProv.packetsReceived}',
                  color: AppConstants.neonCyan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SECTION 2: Performance Metrics
// ═══════════════════════════════════════════════════════════════════

class _PerformanceSection extends StatelessWidget {
  final DiagnosticsProvider diagProv;
  const _PerformanceSection({required this.diagProv});

  @override
  Widget build(BuildContext context) {
    final diag = diagProv.diagnostics;

    return _SectionContainer(
      title: 'PERFORMANCE',
      icon: Icons.speed,
      child: Column(
        children: [
          // FPS + Frame time
          Row(
            children: [
              Expanded(
                child: PerformanceChart(
                  label: 'FPS',
                  value: diag.fps.toStringAsFixed(0),
                  data: diagProv.fpsHistory,
                  lineColor: diag.isFpsLow
                      ? AppConstants.neonRed
                      : AppConstants.neonGreen,
                  minY: 0,
                  maxY: 80,
                  warningThreshold: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: PerformanceChart(
                  label: 'LATENCY',
                  value: diag.latency.toStringAsFixed(1),
                  unit: 'ms',
                  data: diagProv.latencyHistory,
                  lineColor: diag.latency > 50
                      ? AppConstants.neonRed
                      : AppConstants.neonCyan,
                  minY: 0,
                  maxY: 100,
                  warningThreshold: 50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: PerformanceChart(
                  label: 'FREE HEAP',
                  value: _formatHeap(diag.heap),
                  data:
                      diagProv.heapHistory.map((e) => e.toDouble()).toList(),
                  lineColor: diag.isHeapCritical
                      ? AppConstants.neonRed
                      : AppConstants.neonBlue,
                  minY: 0,
                  warningThreshold: 40000,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: PerformanceChart(
                  label: 'PACKET RATE',
                  value: '${diag.packetRate}',
                  unit: 'pkt/s',
                  data: diagProv.packetRateHistory
                      .map((e) => e.toDouble())
                      .toList(),
                  lineColor: AppConstants.neonMagenta,
                  minY: 0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Summary chips
          Row(
            children: [
              _SmallChip(
                label: 'AVG FPS',
                value: diagProv.avgFps.toStringAsFixed(0),
                color: AppConstants.neonGreen,
              ),
              const SizedBox(width: 6),
              _SmallChip(
                label: 'AVG LAT',
                value: '${diagProv.avgLatency.toStringAsFixed(0)}ms',
                color: AppConstants.neonCyan,
              ),
              const SizedBox(width: 6),
              _SmallChip(
                label: 'MIN HEAP',
                value: _formatHeap(diag.minHeap),
                color: AppConstants.neonBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatHeap(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}KB';
    }
    return '${bytes}B';
  }
}

// ═══════════════════════════════════════════════════════════════════
// SECTION 3: Bug Detection Panel
// ═══════════════════════════════════════════════════════════════════

class _BugDetectionSection extends StatelessWidget {
  final DiagnosticsProvider diagProv;
  const _BugDetectionSection({required this.diagProv});

  @override
  Widget build(BuildContext context) {
    final bugs = diagProv.bugs;

    return _SectionContainer(
      title: 'BUG DETECTION',
      icon: Icons.bug_report,
      iconColor: diagProv.hasCriticalAlerts
          ? AppConstants.neonRed
          : AppConstants.neonYellow,
      trailing: bugs.isNotEmpty
          ? GestureDetector(
              onTap: () => diagProv.clearBugs(),
              child: Text(
                'CLEAR',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            )
          : null,
      child: Column(
        children: [
          // Summary chips
          Row(
            children: [
              _BugSeverityChip(
                label: 'CRITICAL',
                count: diagProv.criticalCount,
                color: AppConstants.neonRed,
              ),
              const SizedBox(width: 6),
              _BugSeverityChip(
                label: 'HIGH',
                count: diagProv.highCount,
                color: const Color(0xFFFF4444),
              ),
              const SizedBox(width: 6),
              _BugSeverityChip(
                label: 'MEDIUM',
                count: diagProv.mediumCount,
                color: AppConstants.neonOrange,
              ),
              const SizedBox(width: 6),
              _BugSeverityChip(
                label: 'LOW',
                count: diagProv.lowCount,
                color: AppConstants.neonYellow,
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (bugs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppConstants.neonGreen.withValues(alpha: 0.5),
                      size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No bugs detected',
                    style: TextStyle(
                      color: AppConstants.textDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            // Show latest 10 bugs
            ...bugs
                .take(10)
                .toList()
                .asMap()
                .entries
                .map((e) => BugAlertCard(bug: e.value, index: e.key)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SECTION 4: RTOS Visualization
// ═══════════════════════════════════════════════════════════════════

class _RtosSection extends StatelessWidget {
  final DiagnosticsProvider diagProv;
  final TelemetryProvider telProv;
  const _RtosSection({required this.diagProv, required this.telProv});

  @override
  Widget build(BuildContext context) {
    return RtosVisualization(
      fps: diagProv.fps,
      packetRate: diagProv.packetRate,
      wifiRssi: diagProv.wifiRssi,
      heap: diagProv.heap,
      isConnected: telProv.isConnected,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SHARED COMPONENTS
// ═══════════════════════════════════════════════════════════════════

class _SectionContainer extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;

  const _SectionContainer({
    required this.title,
    required this.icon,
    this.iconColor,
    this.trailing,
    required this.child,
  });

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
              Icon(icon,
                  color: iconColor ?? AppConstants.neonCyan, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool connected;
  const _StatusDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppConstants.neonGreen : AppConstants.neonRed;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.5),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SmallChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.5),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BugSeverityChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _BugSeverityChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.3)
              : AppConstants.borderDim.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: active ? color : AppConstants.textDim.withValues(alpha: 0.5),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
