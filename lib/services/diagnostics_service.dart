import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/diagnostics_data.dart';

/// Manages ESP32 performance diagnostics and telemetry health tracking.
///
/// Responsibilities:
/// - Parse incoming diagnostics packets
/// - Maintain rolling history buffers for chart visualization
/// - Calculate averages for FPS, latency, heap, packet rate
/// - Expose current and historical performance data
///
/// Future-ready for: trend analysis, AI anomaly detection, recording.
class DiagnosticsService {
  /// Max history points per metric (60 points ≈ 30 seconds at 500ms interval).
  static const int maxHistoryPoints = 60;

  /// Current diagnostics snapshot.
  DiagnosticsData _current = DiagnosticsData.empty;

  /// Rolling history buffers.
  final List<double> _fpsHistory = [];
  final List<double> _latencyHistory = [];
  final List<int> _heapHistory = [];
  final List<int> _packetRateHistory = [];
  final List<int> _healthHistory = [];
  final List<int> _rssiHistory = [];

  /// Stream controllers.
  final _diagController = StreamController<DiagnosticsData>.broadcast();
  final _historyController = StreamController<void>.broadcast();

  /// Stream of new diagnostics snapshots.
  Stream<DiagnosticsData> get diagnosticsStream => _diagController.stream;

  /// Stream notifying when history has been updated (for chart repaints).
  Stream<void> get historyStream => _historyController.stream;

  /// Current snapshot.
  DiagnosticsData get current => _current;

  /// Total diagnostics packets processed.
  int _totalProcessed = 0;
  int get totalProcessed => _totalProcessed;

  // ─── History Accessors ────────────────────────────────────────

  List<double> get fpsHistory => List.unmodifiable(_fpsHistory);
  List<double> get latencyHistory => List.unmodifiable(_latencyHistory);
  List<int> get heapHistory => List.unmodifiable(_heapHistory);
  List<int> get packetRateHistory => List.unmodifiable(_packetRateHistory);
  List<int> get healthHistory => List.unmodifiable(_healthHistory);
  List<int> get rssiHistory => List.unmodifiable(_rssiHistory);

  // ─── Averages ─────────────────────────────────────────────────

  double get avgFps =>
      _fpsHistory.isEmpty ? 0 : _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;

  double get avgLatency =>
      _latencyHistory.isEmpty ? 0 : _latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length;

  double get avgHeap =>
      _heapHistory.isEmpty ? 0 : _heapHistory.reduce((a, b) => a + b) / _heapHistory.length;

  double get avgPacketRate =>
      _packetRateHistory.isEmpty ? 0 : _packetRateHistory.reduce((a, b) => a + b) / _packetRateHistory.length;

  double get avgHealth =>
      _healthHistory.isEmpty ? 100 : _healthHistory.reduce((a, b) => a + b) / _healthHistory.length;

  // ─── Core Processing ──────────────────────────────────────────

  /// Processes a raw JSON map identified as a diagnostics packet.
  void processDiagnostics(Map<String, dynamic> json) {
    try {
      _current = DiagnosticsData.fromJson(json);
      _totalProcessed++;

      // Append to histories.
      _appendHistory(_fpsHistory, _current.fps);
      _appendHistory(_latencyHistory, _current.latency);
      _appendIntHistory(_heapHistory, _current.heap);
      _appendIntHistory(_packetRateHistory, _current.packetRate);
      _appendIntHistory(_healthHistory, _current.telemetryHealth);
      _appendIntHistory(_rssiHistory, _current.wifiRssi);

      _diagController.add(_current);
      _historyController.add(null);
    } catch (e) {
      debugPrint('[DiagnosticsService] Parse error: $e');
    }
  }

  void _appendHistory(List<double> buffer, double value) {
    buffer.add(value);
    while (buffer.length > maxHistoryPoints) {
      buffer.removeAt(0);
    }
  }

  void _appendIntHistory(List<int> buffer, int value) {
    buffer.add(value);
    while (buffer.length > maxHistoryPoints) {
      buffer.removeAt(0);
    }
  }

  // ─── Reset ────────────────────────────────────────────────────

  void clearHistory() {
    _fpsHistory.clear();
    _latencyHistory.clear();
    _heapHistory.clear();
    _packetRateHistory.clear();
    _healthHistory.clear();
    _rssiHistory.clear();
    _historyController.add(null);
  }

  // ─── Cleanup ──────────────────────────────────────────────────

  void dispose() {
    _diagController.close();
    _historyController.close();
  }
}
