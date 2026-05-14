/// Data model representing an automation test packet from the ESP32.
///
/// The ESP32 sends testing packets when running automated test scenarios:
/// ```json
/// {
///   "type": "testing",
///   "timestamp": 123456,
///   "test": "Boss Stress Test",
///   "status": "RUNNING",
///   "progress": 45,
///   "details": "Testing projectile overflow handling"
/// }
/// ```
class AutomationTest {
  /// Test name/identifier.
  final String testName;

  /// Current status: RUNNING, PASSED, FAILED, WARNING, CANCELLED.
  final String status;

  /// Progress percentage (0–100). Only relevant for RUNNING tests.
  final int progress;

  /// Human-readable details about what the test is doing.
  final String details;

  /// ESP32 uptime when test packet was created (millis).
  final int espTimestamp;

  /// When the dashboard received this test update.
  final DateTime receivedAt;

  const AutomationTest({
    required this.testName,
    required this.status,
    required this.progress,
    required this.details,
    required this.espTimestamp,
    required this.receivedAt,
  });

  factory AutomationTest.fromJson(Map<String, dynamic> json) {
    return AutomationTest(
      testName: json['test'] as String? ?? 'Unknown Test',
      status: (json['status'] as String? ?? 'RUNNING').toUpperCase(),
      progress: (json['progress'] as num?)?.toInt().clamp(0, 100) ?? 0,
      details: json['details'] as String? ?? '',
      espTimestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      receivedAt: DateTime.now(),
    );
  }

  // ─── Status Helpers ─────────────────────────────────────────

  bool get isRunning => status == 'RUNNING';
  bool get isPassed => status == 'PASSED';
  bool get isFailed => status == 'FAILED';
  bool get isWarning => status == 'WARNING';
  bool get isCancelled => status == 'CANCELLED';

  /// Whether the test has finished (any terminal state).
  bool get isTerminal => isPassed || isFailed || isCancelled;

  /// Formatted timestamp string.
  String get formattedTime {
    final h = receivedAt.hour.toString().padLeft(2, '0');
    final m = receivedAt.minute.toString().padLeft(2, '0');
    final s = receivedAt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Status icon emoji for quick display.
  String get statusIcon {
    switch (status) {
      case 'RUNNING':
        return '⏳';
      case 'PASSED':
        return '✅';
      case 'FAILED':
        return '❌';
      case 'WARNING':
        return '⚠️';
      case 'CANCELLED':
        return '🚫';
      default:
        return '❓';
    }
  }

  @override
  String toString() =>
      'AutomationTest($testName, $status, $progress%, $details)';
}
