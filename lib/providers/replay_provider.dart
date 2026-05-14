import 'dart:async';

import 'package:flutter/material.dart';

import '../models/replay_packet.dart';
import '../models/replay_session.dart';
import '../services/replay_engine_service.dart';
import '../services/session_recorder_service.dart';

/// Application mode: live telemetry or replaying a session.
enum AppMode { live, replay }

/// Provides replay engine + session recorder state to the widget tree.
///
/// Manages the recording ↔ replay lifecycle with a 250ms UI throttle
/// consistent with other providers.
class ReplayProvider extends ChangeNotifier {
  SessionRecorderService _recorder;
  ReplayEngineService _engine;

  AppMode _mode = AppMode.live;
  PlaybackState _playbackState = PlaybackState.stopped;
  int _positionMs = 0;
  ReplayPacket? _lastReplayPacket;

  StreamSubscription? _packetSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;

  // ─── UI Throttle (250ms) ────────────────────────────────────────
  static const int _uiThrottleMs = 250;
  bool _pendingNotify = false;
  Timer? _throttleTimer;

  ReplayProvider()
      : _recorder = SessionRecorderService(),
        _engine = ReplayEngineService();

  ReplayProvider.withServices(this._recorder, this._engine);

  // ─── Getters ────────────────────────────────────────────────────

  AppMode get mode => _mode;
  bool get isLive => _mode == AppMode.live;
  bool get isReplay => _mode == AppMode.replay;

  // Recording
  SessionRecorderService get recorder => _recorder;
  bool get isRecording => _recorder.isRecording;
  int get currentPacketCount => _recorder.currentPacketCount;
  List<ReplaySession> get sessions => _recorder.sessions;

  // Playback
  ReplayEngineService get engine => _engine;
  PlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == PlaybackState.playing;
  bool get isPaused => _playbackState == PlaybackState.paused;
  bool get isStopped => _playbackState == PlaybackState.stopped;
  double get speed => _engine.speed;
  int get positionMs => _positionMs;
  int get totalDurationMs => _engine.totalDurationMs;
  double get progress => _engine.progress;
  ReplaySession? get currentReplaySession => _engine.session;
  ReplayPacket? get lastReplayPacket => _lastReplayPacket;

  // ─── Service Injection ──────────────────────────────────────────

  void updateServices(
    SessionRecorderService recorder,
    ReplayEngineService engine,
  ) {
    if (_recorder != recorder) {
      _recorder = recorder;
    }
    if (_engine != engine) {
      _unsubscribeEngine();
      _engine = engine;
      _subscribeToEngine();
    }
  }

  // ─── Recording Control ──────────────────────────────────────────

  /// Starts recording all incoming packets.
  void startRecording() {
    _recorder.startRecording();
    notifyListeners();
  }

  /// Stops recording and returns the completed session.
  ReplaySession? stopRecording() {
    final session = _recorder.stopRecording();
    if (session != null) {
      _recorder.saveToStorage();
    }
    notifyListeners();
    return session;
  }

  /// Records a packet (called from WebSocket routing).
  void recordPacket(String packetType, Map<String, dynamic> payload) {
    _recorder.recordPacket(packetType, payload);
    // Only throttle-notify periodically to avoid per-packet rebuilds
    _scheduleNotify();
  }

  // ─── Replay Control ─────────────────────────────────────────────

  /// Switches to replay mode with a given session.
  void startReplay(ReplaySession session) {
    _mode = AppMode.replay;
    _engine.loadSession(session);
    _subscribeToEngine();
    _engine.play();
    notifyListeners();
  }

  /// Switches back to live mode.
  void exitReplay() {
    _engine.stop();
    _unsubscribeEngine();
    _mode = AppMode.live;
    _lastReplayPacket = null;
    _positionMs = 0;
    notifyListeners();
  }

  void play() {
    _engine.play();
    notifyListeners();
  }

  void pause() {
    _engine.pause();
    notifyListeners();
  }

  void stop() {
    _engine.stop();
    notifyListeners();
  }

  void seekTo(double position) {
    _engine.seekTo(position);
    notifyListeners();
  }

  void rewind() {
    _engine.rewind();
    notifyListeners();
  }

  void fastForward() {
    _engine.fastForward();
    notifyListeners();
  }

  void setSpeed(double newSpeed) {
    _engine.setSpeed(newSpeed);
    notifyListeners();
  }

  // ─── Session Management ─────────────────────────────────────────

  void deleteSession(String sessionId) {
    _recorder.deleteSession(sessionId);
    _recorder.saveToStorage();
    notifyListeners();
  }

  void clearAllSessions() {
    _recorder.clearAll();
    _recorder.saveToStorage();
    notifyListeners();
  }

  Future<void> loadSessions() async {
    await _recorder.loadFromStorage();
    notifyListeners();
  }

  // ─── Engine Subscriptions ───────────────────────────────────────

  void _subscribeToEngine() {
    _unsubscribeEngine();
    _packetSub = _engine.packetStream.listen((pkt) {
      _lastReplayPacket = pkt;
      _scheduleNotify();
    });
    _positionSub = _engine.positionStream.listen((ms) {
      _positionMs = ms;
      _scheduleNotify();
    });
    _stateSub = _engine.stateStream.listen((state) {
      _playbackState = state;
      if (state == PlaybackState.stopped && _mode == AppMode.replay) {
        // Playback finished naturally
      }
      notifyListeners();
    });
  }

  void _unsubscribeEngine() {
    _packetSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
  }

  // ─── Throttle ───────────────────────────────────────────────────

  void _scheduleNotify() {
    if (_pendingNotify) return;
    _pendingNotify = true;
    _throttleTimer?.cancel();
    _throttleTimer = Timer(
      const Duration(milliseconds: _uiThrottleMs),
      () {
        _pendingNotify = false;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _unsubscribeEngine();
    _recorder.dispose();
    _engine.dispose();
    super.dispose();
  }
}
