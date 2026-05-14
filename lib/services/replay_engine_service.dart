import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/replay_packet.dart';
import '../models/replay_session.dart';
import '../models/telemetry_model.dart';

/// Playback state of the replay engine.
enum PlaybackState { stopped, playing, paused }

/// Plays back a recorded [ReplaySession] with accurate timing.
///
/// Features:
/// - Variable speed playback (0.25x – 4x)
/// - Pause / resume / seek
/// - Per-packet stream output for synchronized UI updates
/// - Timeline position tracking
/// - Non-blocking timer-based playback
class ReplayEngineService {
  ReplaySession? _session;
  PlaybackState _playbackState = PlaybackState.stopped;
  double _speed = 1.0;
  int _currentIndex = 0;
  Timer? _playbackTimer;
  DateTime? _playbackStartTime;
  int _playbackStartMs = 0;

  /// Supported playback speeds.
  static const List<double> speeds = [0.25, 0.5, 1.0, 2.0, 4.0];

  // ─── Output Streams ─────────────────────────────────────────────

  final _packetController = StreamController<ReplayPacket>.broadcast();
  final _telemetryController = StreamController<TelemetryData>.broadcast();
  final _positionController = StreamController<int>.broadcast();
  final _stateController = StreamController<PlaybackState>.broadcast();

  /// Stream of replayed packets (all types).
  Stream<ReplayPacket> get packetStream => _packetController.stream;

  /// Stream of replayed telemetry data (for LED mirror / dashboard).
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  /// Stream of current playback position in milliseconds.
  Stream<int> get positionStream => _positionController.stream;

  /// Stream of playback state changes.
  Stream<PlaybackState> get stateStream => _stateController.stream;

  // ─── State Getters ──────────────────────────────────────────────

  PlaybackState get playbackState => _playbackState;
  double get speed => _speed;
  int get currentIndex => _currentIndex;
  ReplaySession? get session => _session;
  bool get isPlaying => _playbackState == PlaybackState.playing;
  bool get isPaused => _playbackState == PlaybackState.paused;
  bool get isStopped => _playbackState == PlaybackState.stopped;

  int get totalDurationMs => _session?.durationMs ?? 0;

  int get currentPositionMs {
    if (_session == null || _currentIndex <= 0) return 0;
    if (_currentIndex >= _session!.packets.length) {
      return _session!.durationMs;
    }
    return _session!.packets[_currentIndex].relativeMs;
  }

  double get progress {
    if (totalDurationMs <= 0) return 0;
    return currentPositionMs / totalDurationMs;
  }

  /// Current replay packet for overlay display.
  ReplayPacket? get currentPacket {
    if (_session == null || _currentIndex < 0) return null;
    if (_currentIndex >= _session!.packets.length) return null;
    return _session!.packets[_currentIndex];
  }

  // ─── Playback Control ───────────────────────────────────────────

  /// Loads a session for playback.
  void loadSession(ReplaySession session) {
    stop();
    _session = session;
    _currentIndex = 0;
    debugPrint(
        '[Replay] Loaded session: ${session.sessionId} (${session.packetCount} packets)');
  }

  /// Starts or resumes playback.
  void play() {
    if (_session == null || _session!.packets.isEmpty) return;

    if (_playbackState == PlaybackState.paused) {
      // Resume from current position
      _playbackStartTime = DateTime.now();
      _playbackStartMs = currentPositionMs;
    } else {
      // Start from beginning or current index
      _playbackStartTime = DateTime.now();
      _playbackStartMs = currentPositionMs;
    }

    _setPlaybackState(PlaybackState.playing);
    _startPlaybackLoop();
  }

  /// Pauses playback.
  void pause() {
    if (_playbackState != PlaybackState.playing) return;
    _playbackTimer?.cancel();
    _setPlaybackState(PlaybackState.paused);
  }

  /// Stops playback and resets to beginning.
  void stop() {
    _playbackTimer?.cancel();
    _currentIndex = 0;
    _playbackStartTime = null;
    _setPlaybackState(PlaybackState.stopped);
    _positionController.add(0);
  }

  /// Seeks to a specific position (0.0 – 1.0).
  void seekTo(double position) {
    if (_session == null || _session!.packets.isEmpty) return;
    final targetMs = (position * totalDurationMs).round();
    _seekToMs(targetMs);
  }

  /// Seeks to a specific millisecond position.
  void _seekToMs(int targetMs) {
    if (_session == null) return;

    // Binary search for the packet closest to targetMs
    int lo = 0, hi = _session!.packets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_session!.packets[mid].relativeMs < targetMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _currentIndex = lo;
    _positionController.add(currentPositionMs);

    // If playing, restart the timer from the new position
    if (_playbackState == PlaybackState.playing) {
      _playbackTimer?.cancel();
      _playbackStartTime = DateTime.now();
      _playbackStartMs = currentPositionMs;
      _startPlaybackLoop();
    }
  }

  /// Jumps backward by [ms] milliseconds.
  void rewind({int ms = 5000}) {
    final target = (currentPositionMs - ms).clamp(0, totalDurationMs);
    _seekToMs(target);
  }

  /// Jumps forward by [ms] milliseconds.
  void fastForward({int ms = 5000}) {
    final target = (currentPositionMs + ms).clamp(0, totalDurationMs);
    _seekToMs(target);
  }

  /// Sets playback speed.
  void setSpeed(double newSpeed) {
    if (!speeds.contains(newSpeed)) return;
    _speed = newSpeed;
    if (_playbackState == PlaybackState.playing) {
      // Restart timer with new speed reference
      _playbackTimer?.cancel();
      _playbackStartTime = DateTime.now();
      _playbackStartMs = currentPositionMs;
      _startPlaybackLoop();
    }
  }

  // ─── Playback Loop ──────────────────────────────────────────────

  void _startPlaybackLoop() {
    _playbackTimer?.cancel();
    // 16ms tick ≈ 60fps smooth playback
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tick(),
    );
  }

  void _tick() {
    if (_session == null || _playbackStartTime == null) return;
    if (_currentIndex >= _session!.packets.length) {
      // Reached end of session
      _playbackTimer?.cancel();
      _setPlaybackState(PlaybackState.stopped);
      _currentIndex = 0;
      _positionController.add(0);
      return;
    }

    // Calculate how far we are in real time, scaled by speed
    final elapsed = DateTime.now().difference(_playbackStartTime!).inMilliseconds;
    final sessionMs = _playbackStartMs + (elapsed * _speed).round();

    // Emit all packets up to the current session time
    while (_currentIndex < _session!.packets.length) {
      final pkt = _session!.packets[_currentIndex];
      if (pkt.relativeMs > sessionMs) break;

      _packetController.add(pkt);

      // Also emit telemetry for dashboard synchronization
      if (pkt.packetType == 'telemetry') {
        try {
          _telemetryController.add(TelemetryData.fromJson(pkt.payload));
        } catch (_) {
          // Skip malformed telemetry packets
        }
      }

      _currentIndex++;
    }

    _positionController.add(currentPositionMs);
  }

  // ─── Internal ───────────────────────────────────────────────────

  void _setPlaybackState(PlaybackState state) {
    _playbackState = state;
    _stateController.add(state);
  }

  /// Releases all resources.
  void dispose() {
    _playbackTimer?.cancel();
    _packetController.close();
    _telemetryController.close();
    _positionController.close();
    _stateController.close();
  }
}
