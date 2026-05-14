import 'dart:async';

import 'package:flutter/material.dart';

import '../models/telemetry_model.dart';
import '../services/bug_detection_service.dart';
import '../services/command_service.dart';
import '../services/diagnostics_service.dart';
import '../services/event_service.dart';
import '../services/replay_engine_service.dart';
import '../services/session_recorder_service.dart';
import '../services/testing_service.dart';
import '../services/websocket_service.dart' as ws;

/// Provides telemetry state to the widget tree via [ChangeNotifier].
///
/// Wraps [WebSocketService], exposes the latest [TelemetryData],
/// connection state, telemetry rate, enhanced metrics, and connection controls.
///
/// Performance: individual widgets should use [Selector] to avoid
/// unnecessary rebuilds. E.g. the LED strip should only select `telemetry.leds`.
///
/// UI rebuild rate is throttled to max ~16fps regardless of packet rate,
/// preventing flicker when the ESP32 sends 100+ packets/sec.
class TelemetryProvider extends ChangeNotifier {
  final ws.WebSocketService _service = ws.WebSocketService();
  final EventService _eventService = EventService();
  final BugDetectionService _bugService = BugDetectionService();
  final DiagnosticsService _diagService = DiagnosticsService();
  final TestingService _testingService = TestingService();
  final SessionRecorderService _recorderService = SessionRecorderService();
  final ReplayEngineService _replayEngine = ReplayEngineService();
  final CommandService _commandService = CommandService();

  TelemetryData _telemetry = TelemetryData.empty;
  ws.ConnectionState _connectionState = ws.ConnectionState.disconnected;
  double _telemetryRate = 0;
  String _ipAddress = '';
  int _port = 81;
  String? _lastError;
  int _packetsReceived = 0;

  StreamSubscription<TelemetryData>? _telemetrySub;
  StreamSubscription<ws.ConnectionState>? _connectionSub;
  Timer? _rateTimer;

  // ─── UI Throttle (≈16fps cap) ──────────────────────────────────
  /// Minimum ms between UI rebuilds. 60ms ≈ 16fps — smooth for telemetry
  /// while being lightweight on mobile GPUs.
  static const int _uiThrottleMs = 60;
  bool _pendingNotify = false;
  Timer? _throttleTimer;

  // ─── Getters ───────────────────────────────────────────────────

  TelemetryData get telemetry => _telemetry;
  ws.ConnectionState get connectionState => _connectionState;
  double get telemetryRate => _telemetryRate;
  String get ipAddress => _ipAddress;
  int get port => _port;
  String? get lastError => _lastError;
  int get packetsReceived => _packetsReceived;

  bool get isConnected => _connectionState == ws.ConnectionState.connected;
  bool get isConnecting => _connectionState == ws.ConnectionState.connecting;

  // ─── Enhanced Metrics (Phase 1) ────────────────────────────────

  int get reconnectCount => _service.reconnectCount;
  int get packetErrors => _service.packetErrors;
  double get interPacketMs => _service.interPacketMs;
  DateTime? get lastPacketTime => _service.lastPacketTime;
  double get telemetryHealth => _service.telemetryHealth;

  // ─── Service Access ────────────────────────────────────────────

  /// The shared event service instance.
  EventService get eventService => _eventService;

  /// The shared bug detection service instance (Phase 3).
  BugDetectionService get bugService => _bugService;

  /// The shared diagnostics service instance (Phase 3).
  DiagnosticsService get diagService => _diagService;

  /// The shared testing service instance (Phase 4).
  TestingService get testingService => _testingService;

  /// The shared session recorder service (Phase 5).
  SessionRecorderService get recorderService => _recorderService;

  /// The shared replay engine service (Phase 5).
  ReplayEngineService get replayEngine => _replayEngine;

  /// The shared command service (Phase 6).
  CommandService get commandService => _commandService;

  // ─── Future-Ready Hooks ────────────────────────────────────────

  bool get isRecording => _service.isRecording;
  void startRecording() => _service.startRecording();
  List<String>? stopRecording() => _service.stopRecording();
  void sendCommand(String command) => _service.sendCommand(command);

  // ─── Throttled Notify ─────────────────────────────────────────

  /// Schedules a single [notifyListeners] within the throttle window.
  /// Every incoming packet updates [_telemetry] immediately (data is never
  /// stale), but the widget tree rebuild is coalesced: at most one rebuild
  /// fires per [_uiThrottleMs] milliseconds, eliminating the 100+ fps flicker.
  void _scheduleNotify() {
    if (_pendingNotify) return; // a rebuild is already queued — skip
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

  // ─── Connection Control ────────────────────────────────────────

  /// Connects to the ESP32 at [ip]:[port].
  Future<void> connect(String ip, {int port = 81}) async {
    _ipAddress = ip;
    _port = port;
    _lastError = null;
    _packetsReceived = 0;
    notifyListeners();

    // Subscribe to streams
    _telemetrySub?.cancel();
    _connectionSub?.cancel();

    _connectionSub = _service.connectionStateStream.listen((state) {
      final prev = _connectionState;
      _connectionState = state;
      if (state == ws.ConnectionState.error) {
        _lastError = 'Connection failed';
      }
      // Only notify immediately for meaningful transitions.
      // Skip rapid connecting→error→connecting bounce cycles that cause
      // the entire provider tree to rebuild and flicker the UI.
      if (state == ws.ConnectionState.connected ||
          state == ws.ConnectionState.disconnected ||
          (state == ws.ConnectionState.connecting &&
              prev == ws.ConnectionState.disconnected)) {
        notifyListeners();
      } else {
        // Error / reconnecting — throttle to avoid rebuild storm
        _scheduleNotify();
      }
    });

    _telemetrySub = _service.telemetryStream.listen((data) {
      _telemetry = data; // Always store latest data immediately
      _packetsReceived++;
      _scheduleNotify(); // Throttle the UI rebuild to ≤16fps
    });

    // Poll telemetry rate every 500ms — avoids per-packet notify
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final rate = _service.telemetryRate;
      if ((_telemetryRate - rate).abs() > 0.5) {
        _telemetryRate = rate;
        notifyListeners();
      }
    });

    // Wire all services into WebSocket
    _service.eventService = _eventService;
    _service.bugService = _bugService;
    _service.diagService = _diagService;
    _service.testingService = _testingService;
    _service.recorderService = _recorderService;
    _service.commandService = _commandService;

    try {
      await _service.connect(ip, port: port);
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Disconnects from the ESP32.
  Future<void> disconnect() async {
    _throttleTimer?.cancel();
    _rateTimer?.cancel();
    await _service.disconnect();
    _connectionState = ws.ConnectionState.disconnected;
    _telemetryRate = 0;
    notifyListeners();
  }

  /// Reconnects using the last known IP and port.
  Future<void> reconnect() async {
    if (_ipAddress.isNotEmpty) {
      await disconnect();
      _service.autoReconnect = true;
      await connect(_ipAddress, port: _port);
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _rateTimer?.cancel();
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _service.dispose();
    _eventService.dispose();
    _bugService.dispose();
    _diagService.dispose();
    _testingService.dispose();
    _recorderService.dispose();
    _replayEngine.dispose();
    _commandService.dispose();
    super.dispose();
  }
}
