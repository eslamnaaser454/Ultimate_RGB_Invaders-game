import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/telemetry_provider.dart';
import '../services/websocket_service.dart' as ws;
import '../utils/constants.dart';
import '../widgets/accuracy_gauge.dart';
import '../widgets/boss_hp_bar.dart';
import '../widgets/combo_color_widget.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/game_state_badge.dart';
import '../widgets/led_strip_painter.dart';
import '../widgets/stat_card.dart';
import 'connection_screen.dart';

/// Main dashboard screen displaying all live telemetry data.
///
/// Performance optimizations:
/// - LED strip is rendered in its own [_IsolatedLedStrip] widget with a
///   [Selector] that only rebuilds when the `leds` list actually changes.
/// - Stats section uses a separate [Selector] keyed on a snapshot record
///   that excludes the `leds` field, so LED-only changes don't trigger
///   stat card rebuilds.
/// - App bar uses its own [Selector] for connection state only.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─── App Bar (rebuilds on connection state only) ──────
            SliverToBoxAdapter(child: _DashboardAppBar()),

            // ─── Content ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(AppConstants.screenPadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // LED Strip — ISOLATED from other rebuilds
                  const _IsolatedLedStrip(),
                  const SizedBox(height: AppConstants.gridSpacing),

                  // All other stats — rebuild when telemetry (minus LEDs) changes
                  const _TelemetryStatsSection(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ISOLATED LED STRIP
// Only rebuilds when the leds list changes — not on score/state/etc.
// ═══════════════════════════════════════════════════════════════════

class _IsolatedLedStrip extends StatelessWidget {
  const _IsolatedLedStrip();

  @override
  Widget build(BuildContext context) {
    return Selector<TelemetryProvider, List<int>>(
      selector: (_, p) => p.telemetry.leds,
      shouldRebuild: (prev, next) => !listEquals(prev, next),
      builder: (_, leds, __) => LedStripPainterWidget(leds: leds),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// APP BAR — only rebuilds on connection state & rate changes
// ═══════════════════════════════════════════════════════════════════

/// Snapshot of just the fields the app bar cares about.
class _AppBarSnapshot {
  final ws.ConnectionState connectionState;
  final double telemetryRate;
  const _AppBarSnapshot(this.connectionState, this.telemetryRate);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AppBarSnapshot &&
          connectionState == other.connectionState &&
          (telemetryRate - other.telemetryRate).abs() < 0.5;

  @override
  int get hashCode => Object.hash(connectionState, telemetryRate.round());
}

class _DashboardAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<TelemetryProvider, _AppBarSnapshot>(
      selector: (_, p) => _AppBarSnapshot(p.connectionState, p.telemetryRate),
      builder: (context, snap, _) {
        final prov = context.read<TelemetryProvider>();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              // Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RGB INVADERS',
                    style: TextStyle(
                      color: AppConstants.neonCyan,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  Text(
                    'LIVE TELEMETRY',
                    style: TextStyle(
                      color: AppConstants.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Connection indicator
              ConnectionIndicator(
                state: snap.connectionState,
                telemetryRate: snap.telemetryRate,
              ),

              const SizedBox(width: 8),

              // Settings / reconnect
              PopupMenuButton<String>(
                icon:
                    Icon(Icons.more_vert, color: AppConstants.textSecondary),
                color: AppConstants.bgCard,
                onSelected: (v) {
                  if (v == 'reconnect') prov.reconnect();
                  if (v == 'disconnect') {
                    prov.disconnect();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const ConnectionScreen()),
                      (route) => false,
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'reconnect',
                    child: Row(children: [
                      Icon(Icons.refresh,
                          color: AppConstants.neonCyan, size: 18),
                      const SizedBox(width: 8),
                      Text('Reconnect',
                          style:
                              TextStyle(color: AppConstants.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'disconnect',
                    child: Row(children: [
                      Icon(Icons.power_settings_new,
                          color: AppConstants.neonRed, size: 18),
                      const SizedBox(width: 8),
                      Text('Disconnect',
                          style:
                              TextStyle(color: AppConstants.textPrimary)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TELEMETRY STATS SECTION
// Rebuilds when any telemetry value EXCEPT leds changes.
// ═══════════════════════════════════════════════════════════════════

/// Snapshot of non-LED telemetry fields used for Selector comparison.
///
/// IMPORTANT: packetsReceived is excluded from equality because it changes
/// on every packet, which would defeat the Selector optimization.
class _StatsSnapshot {
  final int level, score, bossHP, maxBossHP, enemies, projectiles;
  final int accuracy, comboColor, simonStage;
  final String state, mode;
  final bool beatSaber;
  final String ipAddress;

  const _StatsSnapshot({
    required this.level,
    required this.score,
    required this.bossHP,
    required this.maxBossHP,
    required this.enemies,
    required this.projectiles,
    required this.accuracy,
    required this.comboColor,
    required this.simonStage,
    required this.state,
    required this.mode,
    required this.beatSaber,
    required this.ipAddress,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StatsSnapshot &&
          level == other.level &&
          score == other.score &&
          bossHP == other.bossHP &&
          maxBossHP == other.maxBossHP &&
          enemies == other.enemies &&
          projectiles == other.projectiles &&
          accuracy == other.accuracy &&
          comboColor == other.comboColor &&
          simonStage == other.simonStage &&
          state == other.state &&
          mode == other.mode &&
          beatSaber == other.beatSaber &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => Object.hash(
        level, score, bossHP, maxBossHP, enemies, projectiles,
        accuracy, comboColor, simonStage, state, mode, beatSaber,
        ipAddress,
      );
}

class _TelemetryStatsSection extends StatelessWidget {
  const _TelemetryStatsSection();

  @override
  Widget build(BuildContext context) {
    return Selector<TelemetryProvider, _StatsSnapshot>(
      selector: (_, p) {
        final t = p.telemetry;
        return _StatsSnapshot(
          level: t.level,
          score: t.score,
          bossHP: t.bossHP,
          maxBossHP: t.maxBossHP,
          enemies: t.enemies,
          projectiles: t.projectiles,
          accuracy: t.accuracy,
          comboColor: t.comboColor,
          simonStage: t.simonStage,
          state: t.state,
          mode: t.mode,
          beatSaber: t.beatSaber,
          ipAddress: p.ipAddress,
        );
      },
      builder: (context, snap, _) {
        final prov = context.read<TelemetryProvider>();
        final t = prov.telemetry;

        return Column(
          children: [
            // Game State + Mode
            GameStateBadge(state: t.state, mode: t.mode),
            const SizedBox(height: AppConstants.gridSpacing),

            // Boss HP Bar
            BossHpBar(
              currentHP: t.bossHP,
              maxHP: t.maxBossHP,
              isBossFight: t.isBossFight,
            ),
            const SizedBox(height: AppConstants.gridSpacing),

            // Score + Level row
            Row(children: [
              Expanded(
                  child: StatCard(
                icon: Icons.star,
                label: 'Score',
                value: _formatScore(t.score),
                accentColor: AppConstants.neonYellow,
              )),
              const SizedBox(width: AppConstants.gridSpacing),
              Expanded(
                  child: StatCard(
                icon: Icons.layers,
                label: 'Level',
                value: '${t.level}',
                subtitle: 'of 10',
                accentColor: AppConstants.neonCyan,
              )),
            ]),
            const SizedBox(height: AppConstants.gridSpacing),

            // Enemies + Projectiles row
            Row(children: [
              Expanded(
                  child: StatCard(
                icon: Icons.bug_report,
                label: 'Enemies',
                value: '${t.enemies}',
                accentColor: AppConstants.neonRed,
              )),
              const SizedBox(width: AppConstants.gridSpacing),
              Expanded(
                  child: StatCard(
                icon: Icons.flash_on,
                label: 'Projectiles',
                value: '${t.projectiles}',
                accentColor: AppConstants.neonBlue,
              )),
            ]),
            const SizedBox(height: AppConstants.gridSpacing),

            // Accuracy Gauge + Combo Color
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: AccuracyGauge(accuracy: t.accuracy)),
                const SizedBox(width: AppConstants.gridSpacing),
                Expanded(
                    child:
                        ComboColorWidget(comboColorId: t.comboColor)),
              ],
            ),
            const SizedBox(height: AppConstants.gridSpacing),

            // Bonus modes row
            Row(children: [
              Expanded(
                  child: StatCard(
                icon: Icons.music_note,
                label: 'Simon Stage',
                value: '${t.simonStage}',
                accentColor: AppConstants.neonMagenta,
              )),
              const SizedBox(width: AppConstants.gridSpacing),
              Expanded(
                  child: StatCard(
                icon: Icons.sports_esports,
                label: 'Beat Saber',
                value: t.beatSaber ? 'ACTIVE' : 'OFF',
                accentColor: t.beatSaber
                    ? AppConstants.neonGreen
                    : AppConstants.textDim,
                trailing: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.beatSaber
                        ? AppConstants.neonGreen
                        : AppConstants.textDim,
                  ),
                ),
              )),
            ]),
            const SizedBox(height: AppConstants.gridSpacing),

            // Telemetry stats
            _buildTelemetryInfo(prov),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildTelemetryInfo(TelemetryProvider prov) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppConstants.borderDim),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: AppConstants.textDim, size: 16),
              const SizedBox(width: 8),
              Text(
                'TELEMETRY',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '${prov.packetsReceived} packets',
                style: TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                prov.ipAddress.isNotEmpty
                    ? prov.ipAddress
                    : 'Not connected',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Enhanced metrics row
          Row(
            children: [
              _MetricChip(
                label: 'HEALTH',
                value: '${prov.telemetryHealth.toStringAsFixed(0)}%',
                color: prov.telemetryHealth > 95
                    ? AppConstants.neonGreen
                    : prov.telemetryHealth > 80
                        ? AppConstants.neonYellow
                        : AppConstants.neonRed,
              ),
              const SizedBox(width: 8),
              _MetricChip(
                label: 'ERRORS',
                value: '${prov.packetErrors}',
                color: prov.packetErrors > 0
                    ? AppConstants.neonRed
                    : AppConstants.textDim,
              ),
              const SizedBox(width: 8),
              _MetricChip(
                label: 'RECONN',
                value: '${prov.reconnectCount}',
                color: AppConstants.textDim,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatScore(int score) {
    if (score >= 1000000) return '${(score / 1000000).toStringAsFixed(1)}M';
    if (score >= 1000) return '${(score / 1000).toStringAsFixed(1)}K';
    return '$score';
  }
}

/// Tiny chip for metrics in the telemetry info bar.
class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
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
              color: color.withValues(alpha: 0.6),
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
