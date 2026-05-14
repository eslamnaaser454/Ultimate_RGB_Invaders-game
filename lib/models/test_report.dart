/// Data model representing a completed test report from the ESP32.
///
/// ```json
/// {
///   "type": "test_report",
///   "timestamp": 123456,
///   "test": "Collision Validation",
///   "passed": 120,
///   "failed": 2,
///   "warnings": 5,
///   "duration": 15432
/// }
/// ```
class TestReport {
  /// Test name/identifier.
  final String testName;

  /// Number of assertions that passed.
  final int passed;

  /// Number of assertions that failed.
  final int failed;

  /// Number of warnings generated.
  final int warnings;

  /// Total duration in milliseconds.
  final int durationMs;

  /// ESP32 uptime when report was generated.
  final int espTimestamp;

  /// Dashboard receive time.
  final DateTime receivedAt;

  const TestReport({
    required this.testName,
    required this.passed,
    required this.failed,
    required this.warnings,
    required this.durationMs,
    required this.espTimestamp,
    required this.receivedAt,
  });

  factory TestReport.fromJson(Map<String, dynamic> json) {
    return TestReport(
      testName: json['test'] as String? ?? 'Unknown Test',
      passed: (json['passed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      warnings: (json['warnings'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
      espTimestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      receivedAt: DateTime.now(),
    );
  }

  // ─── Computed Metrics ───────────────────────────────────────

  /// Total assertion count.
  int get totalAssertions => passed + failed + warnings;

  /// Pass rate as percentage (0–100).
  double get passRate {
    if (totalAssertions <= 0) return 0;
    return (passed / totalAssertions * 100).clamp(0, 100);
  }

  /// Failure rate as percentage (0–100).
  double get failRate {
    if (totalAssertions <= 0) return 0;
    return (failed / totalAssertions * 100).clamp(0, 100);
  }

  /// Whether this test passed all assertions.
  bool get isFullyPassed => failed == 0;

  /// Whether the test has any failures.
  bool get hasFailures => failed > 0;

  /// Duration formatted as readable string.
  String get formattedDuration {
    if (durationMs < 1000) return '${durationMs}ms';
    final secs = durationMs / 1000;
    if (secs < 60) return '${secs.toStringAsFixed(1)}s';
    final mins = (secs / 60).floor();
    final remainSecs = (secs % 60).toStringAsFixed(0);
    return '${mins}m ${remainSecs}s';
  }

  /// Formatted timestamp.
  String get formattedTime {
    final h = receivedAt.hour.toString().padLeft(2, '0');
    final m = receivedAt.minute.toString().padLeft(2, '0');
    final s = receivedAt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Overall status string.
  String get statusLabel {
    if (failed > 0) return 'FAILED';
    if (warnings > 0) return 'PASSED (with warnings)';
    return 'PASSED';
  }

  @override
  String toString() =>
      'TestReport($testName, P=$passed F=$failed W=$warnings, $formattedDuration)';
}
