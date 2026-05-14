import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bug_report.dart';

/// Manages the bug detection pipeline from ESP32 runtime assertions.
///
/// Responsibilities:
/// - Receive and parse bug packets
/// - Maintain a rolling buffer of max 100 bug reports
/// - Categorize bugs by severity
/// - Track bug frequency for anomaly detection
/// - Expose active critical alerts
///
/// Future-ready for: AI analysis, automated testing, replay hooks.
class BugDetectionService {
  /// Max bug buffer size.
  static const int maxBugBuffer = 100;

  /// Rolling buffer of bug reports (newest first).
  final List<BugReport> _bugs = [];

  /// Broadcast stream for new individual bugs.
  final _bugController = StreamController<BugReport>.broadcast();

  /// Broadcast stream for full buffer updates.
  final _bufferController = StreamController<List<BugReport>>.broadcast();

  /// Stream of individual new bugs.
  Stream<BugReport> get bugStream => _bugController.stream;

  /// Stream of the full buffer whenever it changes.
  Stream<List<BugReport>> get bufferStream => _bufferController.stream;

  /// Current bug buffer snapshot (newest first).
  List<BugReport> get bugs => List.unmodifiable(_bugs);

  /// Number of bugs in the buffer.
  int get bugCount => _bugs.length;

  /// Total bugs ever processed.
  int _totalProcessed = 0;
  int get totalProcessed => _totalProcessed;

  /// The most recent bug, or null.
  BugReport? get latestBug => _bugs.isNotEmpty ? _bugs.first : null;

  // ─── Severity Counts ──────────────────────────────────────────

  int get criticalCount => _bugs.where((b) => b.isCritical).length;
  int get highCount => _bugs.where((b) => b.isHigh).length;
  int get mediumCount => _bugs.where((b) => b.isMedium).length;
  int get lowCount => _bugs.where((b) => b.isLow).length;

  /// Whether there are active critical alerts.
  bool get hasCriticalAlerts => criticalCount > 0;

  /// Active alerts (HIGH or CRITICAL bugs in the buffer).
  List<BugReport> get activeAlerts =>
      _bugs.where((b) => b.isHigh || b.isCritical).toList();

  // ─── Core Processing ──────────────────────────────────────────

  /// Processes a raw JSON map identified as a bug packet.
  void processBug(Map<String, dynamic> json) {
    try {
      final bug = BugReport.fromJson(json);
      _addBug(bug);
    } catch (e) {
      debugPrint('[BugService] Failed to parse bug: $e');
    }
  }

  void _addBug(BugReport bug) {
    _bugs.insert(0, bug);
    _totalProcessed++;

    while (_bugs.length > maxBugBuffer) {
      _bugs.removeLast();
    }

    _bugController.add(bug);
    _bufferController.add(List.unmodifiable(_bugs));
  }

  // ─── Filtering ────────────────────────────────────────────────

  /// Returns bugs filtered by severity.
  List<BugReport> filterBySeverity(String severity) =>
      _bugs.where((b) => b.severity.toUpperCase() == severity.toUpperCase()).toList();

  /// Returns bugs filtered by bug identifier.
  List<BugReport> filterByType(String bugType) =>
      _bugs.where((b) => b.bug == bugType).toList();

  // ─── Bug Frequency ────────────────────────────────────────────

  /// Returns unique bug types and their counts in the buffer.
  Map<String, int> get bugFrequency {
    final freq = <String, int>{};
    for (final b in _bugs) {
      freq[b.bug] = (freq[b.bug] ?? 0) + 1;
    }
    return freq;
  }

  // ─── Buffer Management ────────────────────────────────────────

  /// Clears all bugs.
  void clearBugs() {
    _bugs.clear();
    _bufferController.add(const []);
  }

  // ─── Cleanup ──────────────────────────────────────────────────

  void dispose() {
    _bugController.close();
    _bufferController.close();
    _bugs.clear();
  }
}
