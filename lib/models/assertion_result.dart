/// Data model representing an assertion result from the ESP32 runtime validator.
///
/// ```json
/// {
///   "type": "assertion",
///   "timestamp": 123456,
///   "assertion": "bossHP >= 0",
///   "result": "PASSED",
///   "severity": "HIGH"
/// }
/// ```
class AssertionResult {
  /// The assertion expression that was evaluated.
  final String assertion;

  /// Result: PASSED, FAILED, WARNING.
  final String result;

  /// Severity of this assertion: LOW, MEDIUM, HIGH, CRITICAL.
  final String severity;

  /// ESP32 uptime (millis).
  final int espTimestamp;

  /// Dashboard receive time.
  final DateTime receivedAt;

  const AssertionResult({
    required this.assertion,
    required this.result,
    required this.severity,
    required this.espTimestamp,
    required this.receivedAt,
  });

  factory AssertionResult.fromJson(Map<String, dynamic> json) {
    return AssertionResult(
      assertion: json['assertion'] as String? ?? 'unknown',
      result: (json['result'] as String? ?? 'FAILED').toUpperCase(),
      severity: (json['severity'] as String? ?? 'MEDIUM').toUpperCase(),
      espTimestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      receivedAt: DateTime.now(),
    );
  }

  // ─── Result Helpers ─────────────────────────────────────────

  bool get isPassed => result == 'PASSED';
  bool get isFailed => result == 'FAILED';
  bool get isWarning => result == 'WARNING';

  // ─── Severity Helpers ───────────────────────────────────────

  bool get isCritical => severity == 'CRITICAL';
  bool get isHigh => severity == 'HIGH';
  bool get isMedium => severity == 'MEDIUM';
  bool get isLow => severity == 'LOW';

  /// Severity index for sorting (0=LOW, 3=CRITICAL).
  int get severityIndex {
    switch (severity) {
      case 'CRITICAL':
        return 3;
      case 'HIGH':
        return 2;
      case 'MEDIUM':
        return 1;
      default:
        return 0;
    }
  }

  /// Formatted timestamp.
  String get formattedTime {
    final h = receivedAt.hour.toString().padLeft(2, '0');
    final m = receivedAt.minute.toString().padLeft(2, '0');
    final s = receivedAt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() =>
      'AssertionResult($assertion, $result, sev=$severity)';
}
