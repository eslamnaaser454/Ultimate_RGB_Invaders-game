import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bug_report.dart';
import '../models/diagnostics_data.dart';
import '../services/bug_detection_service.dart';
import '../services/diagnostics_service.dart';

/// Provides diagnostics and bug detection state to the widget tree.
///
/// Combines [BugDetectionService] and [DiagnosticsService] into a single
/// provider. Uses a throttled notification model identical to
/// [TelemetryProvider] to prevent excessive rebuilds from high-frequency
/// diagnostics packets (every 500ms) and bug bursts.
class DiagnosticsProvider extends ChangeNotifier {
  BugDetectionService _bugService;
  DiagnosticsService _diagService;

  StreamSubscription<BugReport>? _bugSub;
  StreamSubscription<DiagnosticsData>? _diagSub;

  // UI throttle — max ~4 rebuilds/sec for diagnostics (250ms).
  static const int _throttleMs = 250;
  bool _pendingNotify = false;
  Timer? _throttleTimer;

  DiagnosticsProvider()
      : _bugService = BugDetectionService(),
        _diagService = DiagnosticsService() {
    _listen();
  }

  /// Creates a provider using externally-provided services (for sharing
  /// the same service instances wired to WebSocket routing).
  DiagnosticsProvider.withServices(
    BugDetectionService bugService,
    DiagnosticsService diagService,
  )   : _bugService = bugService,
        _diagService = diagService {
    _listen();
  }

  void _listen() {
    _bugSub?.cancel();
    _diagSub?.cancel();

    _bugSub = _bugService.bugStream.listen((_) => _scheduleNotify());
    _diagSub = _diagService.diagnosticsStream.listen((_) => _scheduleNotify());
  }

  /// Replaces the underlying services (used by ProxyProvider updates).
  void updateServices(BugDetectionService bugService, DiagnosticsService diagService) {
    if (_bugService == bugService && _diagService == diagService) return;
    _bugService = bugService;
    _diagService = diagService;
    _listen();
    notifyListeners();
  }

  void _scheduleNotify() {
    if (_pendingNotify) return;
    _pendingNotify = true;
    _throttleTimer?.cancel();
    _throttleTimer = Timer(const Duration(milliseconds: _throttleMs), () {
      _pendingNotify = false;
      notifyListeners();
    });
  }

  // ─── Bug Accessors ────────────────────────────────────────────

  BugDetectionService get bugService => _bugService;

  List<BugReport> get bugs => _bugService.bugs;
  BugReport? get latestBug => _bugService.latestBug;
  int get bugCount => _bugService.bugCount;
  int get totalBugsProcessed => _bugService.totalProcessed;
  bool get hasCriticalAlerts => _bugService.hasCriticalAlerts;
  List<BugReport> get activeAlerts => _bugService.activeAlerts;

  int get criticalCount => _bugService.criticalCount;
  int get highCount => _bugService.highCount;
  int get mediumCount => _bugService.mediumCount;
  int get lowCount => _bugService.lowCount;

  // ─── Diagnostics Accessors ────────────────────────────────────

  DiagnosticsService get diagService => _diagService;

  DiagnosticsData get diagnostics => _diagService.current;
  int get totalDiagnosticsProcessed => _diagService.totalProcessed;

  double get fps => _diagService.current.fps;
  double get frameTime => _diagService.current.frameTime;
  int get heap => _diagService.current.heap;
  int get minHeap => _diagService.current.minHeap;
  int get wifiRssi => _diagService.current.wifiRssi;
  double get latency => _diagService.current.latency;
  int get packetRate => _diagService.current.packetRate;
  int get telemetryHealth => _diagService.current.telemetryHealth;

  // History
  List<double> get fpsHistory => _diagService.fpsHistory;
  List<double> get latencyHistory => _diagService.latencyHistory;
  List<int> get heapHistory => _diagService.heapHistory;
  List<int> get packetRateHistory => _diagService.packetRateHistory;

  // Averages
  double get avgFps => _diagService.avgFps;
  double get avgLatency => _diagService.avgLatency;
  double get avgHeap => _diagService.avgHeap;

  // ─── Actions ──────────────────────────────────────────────────

  void clearBugs() {
    _bugService.clearBugs();
    notifyListeners();
  }

  void clearHistory() {
    _diagService.clearHistory();
    notifyListeners();
  }

  // ─── Cleanup ──────────────────────────────────────────────────

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _bugSub?.cancel();
    _diagSub?.cancel();
    _bugService.dispose();
    _diagService.dispose();
    super.dispose();
  }
}
