import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/telemetry_model.dart';
import 'bug_detection_service.dart';
import 'command_service.dart';
import 'diagnostics_service.dart';
import 'event_service.dart';
import 'session_recorder_service.dart';
import 'testing_service.dart';

/// Connection states for the WebSocket lifecycle.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Manages the WebSocket connection to the ESP32 game controller.
///
/// Features:
/// - Stream-based telemetry delivery
/// - Automatic reconnection with exponential backoff
/// - Telemetry rate (FPS) measurement
/// - Latency & inter-packet timing
/// - Packet error tracking
/// - Reconnect counting
/// - Future-ready: packet recording, command console
/// - Robust error handling
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _telemetryController = StreamController<TelemetryData>.broadcast();
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();

  /// Event service for routing event packets. Injected externally.
  EventService? _eventService;

  /// Bug detection service for routing bug packets. Injected externally.
  BugDetectionService? _bugService;

  /// Diagnostics service for routing diagnostics packets. Injected externally.
  DiagnosticsService? _diagService;

  /// Testing service for routing testing/assertion/report packets. Injected externally.
  TestingService? _testingService;

  /// Session recorder for Phase 5 replay recording. Injected externally.
  SessionRecorderService? _recorderService;

  /// Command service for Phase 6 command/bot routing. Injected externally.
  CommandService? _commandService;

  ConnectionState _state = ConnectionState.disconnected;
  String? _currentUrl;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 50;

  /// Whether auto-reconnect is enabled.
  bool autoReconnect = true;

  // ─── Telemetry Rate Tracking ───────────────────────────────────
  final List<DateTime> _packetTimestamps = [];
  double _telemetryRate = 0;

  // ─── Enhanced Metrics (Phase 1) ────────────────────────────────
  int _reconnectCount = 0;
  int _packetErrors = 0;
  int _totalPackets = 0;
  DateTime? _lastPacketTime;
  double _interPacketMs = 0;

  // ─── Future-Ready: Packet Recording ────────────────────────────
  List<String>? _recordingBuffer;

  /// Injects the event service for routing event packets.
  set eventService(EventService service) => _eventService = service;

  /// Injects the bug detection service for routing bug packets.
  set bugService(BugDetectionService service) => _bugService = service;

  /// Injects the diagnostics service for routing diagnostics packets.
  set diagService(DiagnosticsService service) => _diagService = service;

  /// Injects the testing service for routing testing packets.
  set testingService(TestingService service) => _testingService = service;

  /// Injects the session recorder service for packet recording.
  set recorderService(SessionRecorderService service) => _recorderService = service;

  /// Injects the command service for routing Phase 6 packets.
  set commandService(CommandService service) => _commandService = service;

  /// Stream of parsed telemetry data.
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Current connection state.
  ConnectionState get state => _state;

  /// Measured telemetry packets per second.
  double get telemetryRate => _telemetryRate;

  /// Total reconnect attempts that completed a new connection.
  int get reconnectCount => _reconnectCount;

  /// Number of malformed/unparseable packets received.
  int get packetErrors => _packetErrors;

  /// Total raw packets received (including errored ones).
  int get totalPackets => _totalPackets;

  /// Time of last successfully parsed packet.
  DateTime? get lastPacketTime => _lastPacketTime;

  /// Milliseconds between last two successfully parsed packets.
  double get interPacketMs => _interPacketMs;

  /// Whether packet recording is active.
  bool get isRecording => _recordingBuffer != null;

  /// Telemetry health as a percentage (valid / total * 100).
  double get telemetryHealth {
    if (_totalPackets == 0) return 100;
    return ((_totalPackets - _packetErrors) / _totalPackets * 100)
        .clamp(0, 100);
  }

  /// Connects to the ESP32 WebSocket server at the given [ipAddress] and [port].
  Future<void> connect(String ipAddress, {int port = 81}) async {
    if (_state == ConnectionState.connecting) return;

    _currentUrl = 'ws://$ipAddress:$port';
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setState(ConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_currentUrl!));

      // Wait for the connection to be ready
      await _channel!.ready;

      _setState(ConnectionState.connected);
      // Count reconnects (skip the initial connect)
      if (_reconnectAttempts > 0) {
        _reconnectCount++;
      }
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WebSocket] Connection failed: $e');
      _setState(ConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    _totalPackets++;

    // Future-ready: record raw packet if recording
    if (_recordingBuffer != null) {
      _recordingBuffer!.add(data as String);
    }

    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final packetType = json['type'] as String?;

      // Phase 5: Record packet for replay
      if (_recorderService != null && packetType != null) {
        _recorderService!.recordPacket(packetType, json);
      }

      // Route event packets to EventService
      if (packetType == 'event' && _eventService != null) {
        _eventService!.processEvent(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route bug packets to BugDetectionService
      if (packetType == 'bug' && _bugService != null) {
        _bugService!.processBug(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route diagnostics packets to DiagnosticsService
      if (packetType == 'diagnostics' && _diagService != null) {
        _diagService!.processDiagnostics(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route testing packets to TestingService (Phase 4)
      if (packetType == 'testing' && _testingService != null) {
        _testingService!.processTest(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route assertion packets to TestingService (Phase 4)
      if (packetType == 'assertion' && _testingService != null) {
        _testingService!.processAssertion(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route test_report packets to TestingService (Phase 4)
      if (packetType == 'test_report' && _testingService != null) {
        _testingService!.processReport(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route command_response packets to CommandService (Phase 6)
      if (packetType == 'command_response' && _commandService != null) {
        _commandService!.processCommandResponse(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route bot_status packets to CommandService (Phase 6)
      if (packetType == 'bot_status' && _commandService != null) {
        _commandService!.processBotStatus(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Route input_action packets to CommandService (Phase 6)
      if (packetType == 'input_action' && _commandService != null) {
        _commandService!.processInputAction(json);
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      // Only parse actual telemetry packets
      if (packetType != 'telemetry') {
        _updateRate();
        _updateInterPacketTime();
        return;
      }

      final telemetry = TelemetryData.fromJson(json);
      _telemetryController.add(telemetry);
      _updateRate();
      _updateInterPacketTime();
    } catch (e) {
      _packetErrors++;
      debugPrint('[WebSocket] Parse error: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('[WebSocket] Stream error: $error');
    _setState(ConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WebSocket] Connection closed');
    _setState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _setState(ConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  // ─── Reconnection ─────────────────────────────────────────────

  void _scheduleReconnect() {
    if (!autoReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[WebSocket] Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    final delay = Duration(
      milliseconds: min(1000 * pow(2, _reconnectAttempts).toInt(), 30000),
    );
    _reconnectAttempts++;

    debugPrint(
        '[WebSocket] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      await _cleanup();
      await _doConnect();
    });
  }

  // ─── Rate Measurement ─────────────────────────────────────────

  void _updateRate() {
    final now = DateTime.now();
    _packetTimestamps.add(now);

    // Keep only last 2 seconds of timestamps
    final cutoff = now.subtract(const Duration(seconds: 2));
    _packetTimestamps.removeWhere((t) => t.isBefore(cutoff));

    if (_packetTimestamps.length >= 2) {
      final spanMs = _packetTimestamps.last
          .difference(_packetTimestamps.first)
          .inMilliseconds;
      if (spanMs > 0) {
        _telemetryRate = (_packetTimestamps.length - 1) / (spanMs / 1000.0);
      }
    }
  }

  // ─── Inter-Packet Timing ──────────────────────────────────────

  void _updateInterPacketTime() {
    final now = DateTime.now();
    if (_lastPacketTime != null) {
      _interPacketMs =
          now.difference(_lastPacketTime!).inMicroseconds / 1000.0;
    }
    _lastPacketTime = now;
  }

  // ─── Future-Ready: Command Console ────────────────────────────

  /// Sends a raw command string to the ESP32 via WebSocket.
  void sendCommand(String command) {
    if (_state == ConnectionState.connected && _channel != null) {
      _channel!.sink.add(command);
    }
  }

  // ─── Future-Ready: Packet Recording ───────────────────────────

  /// Starts recording all incoming raw packets.
  void startRecording() => _recordingBuffer = [];

  /// Stops recording and returns the buffer of raw JSON strings.
  List<String>? stopRecording() {
    final buffer = _recordingBuffer;
    _recordingBuffer = null;
    return buffer;
  }

  // ─── Disconnect / Cleanup ─────────────────────────────────────

  /// Disconnects from the WebSocket server.
  Future<void> disconnect() async {
    autoReconnect = false;
    _reconnectTimer?.cancel();
    await _cleanup();
    _setState(ConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// Releases all resources. Call when the service is no longer needed.
  void dispose() {
    _reconnectTimer?.cancel();
    _cleanup();
    _telemetryController.close();
    _connectionStateController.close();
  }
}
