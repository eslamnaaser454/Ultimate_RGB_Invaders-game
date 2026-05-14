import 'dart:async';

import 'package:flutter/material.dart';

import '../models/assertion_result.dart';
import '../models/automation_test.dart';
import '../models/test_report.dart';
import '../services/testing_service.dart';

/// Provides automation testing state to the widget tree via [ChangeNotifier].
///
/// Wraps [TestingService] and uses a throttled notification model (250ms)
/// consistent with [DiagnosticsProvider] to prevent excessive rebuilds
/// from high-frequency test/assertion packets.
class TestingProvider extends ChangeNotifier {
  TestingService _service;

  StreamSubscription<AutomationTest>? _testSub;
  StreamSubscription<AssertionResult>? _assertionSub;
  StreamSubscription<TestReport>? _reportSub;

  // UI throttle — max ~4 rebuilds/sec (250ms).
  static const int _throttleMs = 250;
  bool _pendingNotify = false;
  Timer? _throttleTimer;

  TestingProvider() : _service = TestingService() {
    _listen();
  }

  /// Creates a provider using an externally-provided service (for sharing
  /// the same instance wired to WebSocket routing).
  TestingProvider.withService(TestingService service) : _service = service {
    _listen();
  }

  void _listen() {
    _testSub?.cancel();
    _assertionSub?.cancel();
    _reportSub?.cancel();

    _testSub = _service.testStream.listen((_) => _scheduleNotify());
    _assertionSub = _service.assertionStream.listen((_) => _scheduleNotify());
    _reportSub = _service.reportStream.listen((_) => _scheduleNotify());
  }

  /// Replaces the underlying service (used by ProxyProvider updates).
  void updateService(TestingService service) {
    if (_service == service) return;
    _service = service;
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

  // ─── Service Access ──────────────────────────────────────────

  TestingService get service => _service;

  // ─── Test Accessors ──────────────────────────────────────────

  List<AutomationTest> get activeTests => _service.activeTests;
  List<AutomationTest> get completedTests => _service.completedTests;
  List<AutomationTest> get failedTests => _service.failedTests;
  int get totalTests => _service.totalTests;

  // ─── Assertion Accessors ─────────────────────────────────────

  List<AssertionResult> get assertions => _service.assertions;
  int get totalAssertions => _service.totalAssertions;
  int get assertionsPassed => _service.assertionsPassed;
  int get assertionsFailed => _service.assertionsFailed;
  int get assertionsWarning => _service.assertionsWarning;
  double get assertionPassRate => _service.assertionPassRate;

  // ─── Report Accessors ────────────────────────────────────────

  List<TestReport> get reports => _service.reports;
  int get totalReports => _service.totalReports;
  double get testPassRate => _service.testPassRate;
  double get avgTestDurationMs => _service.avgTestDurationMs;

  // ─── Analytics ───────────────────────────────────────────────

  List<MapEntry<String, int>> get topFailedAssertions =>
      _service.topFailedAssertions;

  // ─── Actions ─────────────────────────────────────────────────

  void clearAll() {
    _service.clearAll();
    notifyListeners();
  }

  // ─── Cleanup ─────────────────────────────────────────────────

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _testSub?.cancel();
    _assertionSub?.cancel();
    _reportSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
