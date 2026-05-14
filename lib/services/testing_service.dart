import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assertion_result.dart';
import '../models/automation_test.dart';
import '../models/test_report.dart';

/// Service managing the automation testing pipeline from ESP32.
///
/// Handles three packet types:
/// - `testing` → active test updates (status, progress)
/// - `assertion` → individual assertion results
/// - `test_report` → completed test summaries
///
/// Maintains rolling buffers and aggregated statistics.
/// Future-ready for: replay engine, AI analysis, scripted test runners.
class TestingService {
  /// Maximum buffer sizes.
  static const int maxActiveTests = 50;
  static const int maxAssertionBuffer = 200;
  static const int maxReportBuffer = 50;
  static const int maxTimelineBuffer = 150;

  // ─── Internal Buffers ────────────────────────────────────────

  /// Map of test name → latest test update (tracks active tests).
  final Map<String, AutomationTest> _activeTests = {};

  /// Rolling buffer of all assertion results (newest first).
  final List<AssertionResult> _assertions = [];

  /// Rolling buffer of completed test reports (newest first).
  final List<TestReport> _reports = [];

  /// Unified timeline of all testing events (newest first).
  final List<TestTimelineEntry> _timeline = [];

  // ─── Counters ────────────────────────────────────────────────

  int _totalTests = 0;
  int _totalAssertions = 0;
  int _totalReports = 0;
  int _assertionsPassed = 0;
  int _assertionsFailed = 0;
  int _assertionsWarning = 0;

  // ─── Streams ─────────────────────────────────────────────────

  final _testController = StreamController<AutomationTest>.broadcast();
  final _assertionController = StreamController<AssertionResult>.broadcast();
  final _reportController = StreamController<TestReport>.broadcast();

  Stream<AutomationTest> get testStream => _testController.stream;
  Stream<AssertionResult> get assertionStream => _assertionController.stream;
  Stream<TestReport> get reportStream => _reportController.stream;

  // ─── Public Accessors ────────────────────────────────────────

  /// All currently tracked tests (latest update per test name).
  List<AutomationTest> get activeTests =>
      _activeTests.values.where((t) => t.isRunning).toList();

  /// All completed tests (terminal state).
  List<AutomationTest> get completedTests =>
      _activeTests.values.where((t) => t.isTerminal).toList();

  /// All failed tests.
  List<AutomationTest> get failedTests =>
      _activeTests.values.where((t) => t.isFailed).toList();

  /// Assertion buffer (newest first).
  List<AssertionResult> get assertions => List.unmodifiable(_assertions);

  /// Report buffer (newest first).
  List<TestReport> get reports => List.unmodifiable(_reports);

  /// Unified timeline (newest first).
  List<TestTimelineEntry> get timeline => List.unmodifiable(_timeline);

  int get totalTests => _totalTests;
  int get totalAssertions => _totalAssertions;
  int get totalReports => _totalReports;
  int get assertionsPassed => _assertionsPassed;
  int get assertionsFailed => _assertionsFailed;
  int get assertionsWarning => _assertionsWarning;

  /// Overall assertion pass rate (0–100).
  double get assertionPassRate {
    final total = _assertionsPassed + _assertionsFailed + _assertionsWarning;
    if (total <= 0) return 100;
    return (_assertionsPassed / total * 100).clamp(0, 100);
  }

  /// Overall test pass rate from reports.
  double get testPassRate {
    if (_reports.isEmpty) return 100;
    final passed = _reports.where((r) => r.isFullyPassed).length;
    return (passed / _reports.length * 100).clamp(0, 100);
  }

  /// Average test duration from reports (ms).
  double get avgTestDurationMs {
    if (_reports.isEmpty) return 0;
    final total = _reports.fold<int>(0, (sum, r) => sum + r.durationMs);
    return total / _reports.length;
  }

  /// Most frequently failed assertions (top 5).
  List<MapEntry<String, int>> get topFailedAssertions {
    final freq = <String, int>{};
    for (final a in _assertions.where((a) => a.isFailed)) {
      freq[a.assertion] = (freq[a.assertion] ?? 0) + 1;
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  // ─── Packet Processing ───────────────────────────────────────

  /// Processes a `type: "testing"` packet.
  void processTest(Map<String, dynamic> json) {
    try {
      final test = AutomationTest.fromJson(json);
      _activeTests[test.testName] = test;
      _totalTests++;

      // Prune oldest entries if map exceeds limit
      if (_activeTests.length > maxActiveTests) {
        final oldest = _activeTests.entries.first.key;
        _activeTests.remove(oldest);
      }

      _addTimeline(test.testName, 'TEST', test.status, test.receivedAt);
      _testController.add(test);
    } catch (e) {
      debugPrint('[TestingService] Failed to parse test: $e');
    }
  }

  /// Processes a `type: "assertion"` packet.
  void processAssertion(Map<String, dynamic> json) {
    try {
      final assertion = AssertionResult.fromJson(json);
      _assertions.insert(0, assertion);
      _totalAssertions++;

      if (assertion.isPassed) _assertionsPassed++;
      if (assertion.isFailed) _assertionsFailed++;
      if (assertion.isWarning) _assertionsWarning++;

      while (_assertions.length > maxAssertionBuffer) {
        _assertions.removeLast();
      }

      _addTimeline(
        assertion.assertion,
        'ASSERTION',
        assertion.result,
        assertion.receivedAt,
      );
      _assertionController.add(assertion);
    } catch (e) {
      debugPrint('[TestingService] Failed to parse assertion: $e');
    }
  }

  /// Processes a `type: "test_report"` packet.
  void processReport(Map<String, dynamic> json) {
    try {
      final report = TestReport.fromJson(json);
      _reports.insert(0, report);
      _totalReports++;

      while (_reports.length > maxReportBuffer) {
        _reports.removeLast();
      }

      _addTimeline(
        report.testName,
        'REPORT',
        report.statusLabel,
        report.receivedAt,
      );
      _reportController.add(report);
    } catch (e) {
      debugPrint('[TestingService] Failed to parse report: $e');
    }
  }

  void _addTimeline(
      String label, String category, String status, DateTime time) {
    _timeline.insert(0, TestTimelineEntry(label, category, status, time));
    while (_timeline.length > maxTimelineBuffer) {
      _timeline.removeLast();
    }
  }

  // ─── Buffer Management ───────────────────────────────────────

  void clearAll() {
    _activeTests.clear();
    _assertions.clear();
    _reports.clear();
    _timeline.clear();
    _totalTests = 0;
    _totalAssertions = 0;
    _totalReports = 0;
    _assertionsPassed = 0;
    _assertionsFailed = 0;
    _assertionsWarning = 0;
  }

  // ─── Cleanup ─────────────────────────────────────────────────

  void dispose() {
    _testController.close();
    _assertionController.close();
    _reportController.close();
    _activeTests.clear();
    _assertions.clear();
    _reports.clear();
    _timeline.clear();
  }
}

/// Timeline entry combining all testing event types.
class TestTimelineEntry {
  final String label;
  final String category; // TEST, ASSERTION, REPORT
  final String status;
  final DateTime time;

  const TestTimelineEntry(this.label, this.category, this.status, this.time);
}
