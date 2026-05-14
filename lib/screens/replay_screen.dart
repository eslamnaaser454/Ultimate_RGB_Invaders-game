import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/replay_session.dart';
import '../providers/replay_provider.dart';
import '../services/replay_engine_service.dart';
import '../utils/constants.dart';

/// Phase 5: Replay Engine + Session History screen.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});
  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReplayProvider>().loadSessions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: SafeArea(
        child: Consumer<ReplayProvider>(
          builder: (context, prov, _) {
            if (prov.isReplay) {
              return _ReplayPlaybackView(prov: prov);
            }
            return _SessionListView(prov: prov);
          },
        ),
      ),
    );
  }
}

// ─── Session List View ───────────────────────────────────────────

class _SessionListView extends StatelessWidget {
  final ReplayProvider prov;
  const _SessionListView({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.replay_circle_filled_rounded,
                  color: AppConstants.neonCyan, size: 28),
              const SizedBox(width: 10),
              Text('REPLAY ENGINE',
                  style: TextStyle(
                      color: AppConstants.neonCyan,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
              const Spacer(),
              _RecordButton(prov: prov),
            ],
          ),
        ),
        // Recording indicator
        if (prov.isRecording) _RecordingBanner(prov: prov),
        // Stats row
        _StatsRow(prov: prov),
        const SizedBox(height: 8),
        // Session list
        Expanded(
          child: prov.sessions.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: prov.sessions.length,
                  itemBuilder: (ctx, i) =>
                      _SessionCard(session: prov.sessions[i], prov: prov),
                ),
        ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  final ReplayProvider prov;
  const _RecordButton({required this.prov});

  @override
  Widget build(BuildContext context) {
    final recording = prov.isRecording;
    return GestureDetector(
      onTap: () {
        if (recording) {
          prov.stopRecording();
        } else {
          prov.startRecording();
        }
      },
      child: AnimatedContainer(
        duration: AppConstants.fastAnim,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: recording
              ? AppConstants.neonRed.withValues(alpha: 0.15)
              : AppConstants.neonCyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: recording
                ? AppConstants.neonRed.withValues(alpha: 0.5)
                : AppConstants.neonCyan.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recording ? Icons.stop_rounded : Icons.fiber_manual_record,
              color: recording ? AppConstants.neonRed : AppConstants.neonCyan,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              recording ? 'STOP' : 'REC',
              style: TextStyle(
                color: recording ? AppConstants.neonRed : AppConstants.neonCyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  final ReplayProvider prov;
  const _RecordingBanner({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppConstants.neonRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppConstants.neonRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record,
              color: AppConstants.neonRed, size: 12),
          const SizedBox(width: 8),
          Text('RECORDING',
              style: TextStyle(
                  color: AppConstants.neonRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          const Spacer(),
          Text('${prov.currentPacketCount} pkts',
              style: TextStyle(
                  color: AppConstants.neonRed.withValues(alpha: 0.7),
                  fontSize: 11)),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final ReplayProvider prov;
  const _StatsRow({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _MiniStat(label: 'SESSIONS', value: '${prov.sessions.length}'),
          _MiniStat(
              label: 'TOTAL PKTS',
              value: '${prov.sessions.fold<int>(0, (s, e) => s + e.packetCount)}'),
          _MiniStat(
              label: 'MODE',
              value: prov.isLive ? 'LIVE' : 'REPLAY',
              color: prov.isLive
                  ? AppConstants.neonGreen
                  : AppConstants.neonMagenta),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppConstants.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppConstants.borderDim),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color ?? AppConstants.neonCyan,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: AppConstants.textDim,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded,
              color: AppConstants.neonCyan.withValues(alpha: 0.3), size: 48),
          const SizedBox(height: 16),
          Text('NO SESSIONS RECORDED',
              style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          Text('Tap REC to start capturing packets',
              style: TextStyle(
                  color: AppConstants.textDim.withValues(alpha: 0.6),
                  fontSize: 11)),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ReplaySession session;
  final ReplayProvider prov;
  const _SessionCard({required this.session, required this.prov});

  @override
  Widget build(BuildContext context) {
    final time =
        '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
    final date =
        '${session.startTime.day}/${session.startTime.month}/${session.startTime.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderDim),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => prov.startReplay(session),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        color: AppConstants.neonCyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$date  $time',
                          style: TextStyle(
                              color: AppConstants.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppConstants.neonCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(session.durationFormatted,
                          style: TextStyle(
                              color: AppConstants.neonCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => prov.deleteSession(session.sessionId),
                      child: Icon(Icons.delete_outline_rounded,
                          color: AppConstants.textDim, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _PktChip('TEL', session.telemetryCount, AppConstants.neonCyan),
                    _PktChip('EVT', session.eventsCount, AppConstants.neonGreen),
                    _PktChip('BUG', session.bugsCount, AppConstants.neonRed),
                    _PktChip('DIAG', session.diagnosticsCount, AppConstants.neonBlue),
                    _PktChip('AST', session.assertionsCount, AppConstants.neonYellow),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PktChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _PktChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text('$label $count',
          style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Replay Playback View ────────────────────────────────────────

class _ReplayPlaybackView extends StatelessWidget {
  final ReplayProvider prov;
  const _ReplayPlaybackView({required this.prov});

  @override
  Widget build(BuildContext context) {
    final session = prov.currentReplaySession;
    if (session == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Header with exit
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => prov.exitReplay(),
                child: Icon(Icons.arrow_back_rounded,
                    color: AppConstants.neonCyan, size: 24),
              ),
              const SizedBox(width: 12),
              Icon(Icons.replay_rounded,
                  color: AppConstants.neonMagenta, size: 22),
              const SizedBox(width: 8),
              Text('REPLAY MODE',
                  style: TextStyle(
                      color: AppConstants.neonMagenta,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.neonMagenta.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppConstants.neonMagenta.withValues(alpha: 0.3)),
                ),
                child: Text('${prov.speed}x',
                    style: TextStyle(
                        color: AppConstants.neonMagenta,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        // Replay overlay info
        _ReplayOverlay(prov: prov, session: session),
        const Spacer(),
        // Analytics
        _SessionAnalytics(session: session),
        const Spacer(),
        // Timeline slider
        _TimelineSlider(prov: prov),
        // Playback controls
        _PlaybackControls(prov: prov),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ReplayOverlay extends StatelessWidget {
  final ReplayProvider prov;
  final ReplaySession session;
  const _ReplayOverlay({required this.prov, required this.session});

  @override
  Widget build(BuildContext context) {
    final pkt = prov.lastReplayPacket;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppConstants.neonMagenta.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: AppConstants.neonMagenta.withValues(alpha: 0.05),
              blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CURRENT PACKET',
                  style: TextStyle(
                      color: AppConstants.textDim,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
              const Spacer(),
              Text(
                  '${_formatMs(prov.positionMs)} / ${session.durationFormatted}',
                  style: TextStyle(
                      color: AppConstants.neonCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          if (pkt != null) ...[
            Row(
              children: [
                _TypeBadge(pkt.packetType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _packetSummary(pkt),
                    style: TextStyle(
                        color: AppConstants.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else
            Text('Waiting...',
                style: TextStyle(
                    color: AppConstants.textDim, fontSize: 11)),
        ],
      ),
    );
  }

  String _packetSummary(dynamic pkt) {
    final p = pkt.payload as Map<String, dynamic>;
    switch (pkt.packetType) {
      case 'telemetry':
        return 'Score: ${p['score']}  Level: ${p['level']}  State: ${p['state']}';
      case 'event':
        return '${p['event']}  severity: ${p['severity']}';
      case 'bug':
        return '${p['bug']}  severity: ${p['severity']}';
      case 'diagnostics':
        return 'FPS: ${p['fps']}  Heap: ${p['heap']}  RSSI: ${p['wifiRssi']}';
      case 'assertion':
        return '${p['assertion']}  → ${p['result']}';
      case 'testing':
        return '${p['test']}  ${p['status']}  ${p['progress']}%';
      case 'test_report':
        return '${p['test']}  P:${p['passed']} F:${p['failed']}';
      default:
        return pkt.packetType;
    }
  }

  String _formatMs(int ms) {
    final secs = ms ~/ 1000;
    final mins = secs ~/ 60;
    final remSecs = secs % 60;
    return '${mins.toString().padLeft(2, '0')}:${remSecs.toString().padLeft(2, '0')}';
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  Color get _color {
    switch (type) {
      case 'telemetry': return AppConstants.neonCyan;
      case 'event': return AppConstants.neonGreen;
      case 'bug': return AppConstants.neonRed;
      case 'diagnostics': return AppConstants.neonBlue;
      case 'assertion': return AppConstants.neonYellow;
      case 'testing': return AppConstants.neonOrange;
      case 'test_report': return AppConstants.neonMagenta;
      default: return AppConstants.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(type.toUpperCase(),
          style: TextStyle(
              color: _color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

class _SessionAnalytics extends StatelessWidget {
  final ReplaySession session;
  const _SessionAnalytics({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SESSION ANALYTICS',
              style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              _AnalyticTile('PACKETS', '${session.packetCount}', AppConstants.neonCyan),
              _AnalyticTile('EVENTS', '${session.eventsCount}', AppConstants.neonGreen),
              _AnalyticTile('BUGS', '${session.bugsCount}', AppConstants.neonRed),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _AnalyticTile('AVG FPS', session.avgFps.toStringAsFixed(0), AppConstants.neonBlue),
              _AnalyticTile('FAIL AST', '${session.failedAssertions}', AppConstants.neonYellow),
              _AnalyticTile('DURATION', session.durationFormatted, AppConstants.neonMagenta),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalyticTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AnalyticTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _TimelineSlider extends StatelessWidget {
  final ReplayProvider prov;
  const _TimelineSlider({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppConstants.neonMagenta,
              inactiveTrackColor: AppConstants.borderDim,
              thumbColor: AppConstants.neonCyan,
              overlayColor: AppConstants.neonCyan.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: prov.progress.clamp(0.0, 1.0),
              onChanged: (v) => prov.seekTo(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final ReplayProvider prov;
  const _PlaybackControls({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppConstants.neonMagenta.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Speed down
          _CtrlBtn(
            icon: Icons.speed_rounded,
            label: '${prov.speed}x',
            onTap: () {
              final speeds = ReplayEngineService.speeds;
              final idx = speeds.indexOf(prov.speed);
              if (idx < speeds.length - 1) {
                prov.setSpeed(speeds[idx + 1]);
              } else {
                prov.setSpeed(speeds[0]);
              }
            },
            color: AppConstants.neonOrange,
          ),
          // Rewind
          _CtrlBtn(
            icon: Icons.replay_5_rounded,
            onTap: () => prov.rewind(),
            color: AppConstants.neonCyan,
          ),
          // Play / Pause
          _CtrlBtn(
            icon: prov.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            onTap: () {
              if (prov.isPlaying) {
                prov.pause();
              } else {
                prov.play();
              }
            },
            color: AppConstants.neonMagenta,
            size: 42,
          ),
          // Fast Forward
          _CtrlBtn(
            icon: Icons.forward_5_rounded,
            onTap: () => prov.fastForward(),
            color: AppConstants.neonCyan,
          ),
          // Stop
          _CtrlBtn(
            icon: Icons.stop_circle_rounded,
            onTap: () => prov.stop(),
            color: AppConstants.neonRed,
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color color;
  final double size;
  const _CtrlBtn({
    required this.icon,
    this.label,
    required this.onTap,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: size),
          if (label != null) ...[
            const SizedBox(height: 2),
            Text(label!,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}
