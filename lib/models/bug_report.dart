/// Data model representing a bug report from the ESP32 runtime validator.
///
/// The ESP32 sends bug packets over WebSocket:
/// ```json
/// {
///   "type": "bug",
///   "severity": "HIGH",
///   "bug": "NEGATIVE_HP",
///   "timestamp": 123456,
///   "state": "BOSS",
///   "level": 10,
///   "details": "Boss HP became negative"
/// }
/// ```
class BugReport {
  /// The bug identifier (e.g. "NEGATIVE_HP", "IMPOSSIBLE_COMBO").
  final String bug;

  /// Severity level: "LOW", "MEDIUM", "HIGH", or "CRITICAL".
  final String severity;

  /// When the bug was received by the dashboard.
  final DateTime timestamp;

  /// Game state at the time of the bug (e.g. "BOSS", "PLAYING").
  final String? state;

  /// Game level at the time of the bug.
  final int? level;

  /// Human-readable details about the bug.
  final String? details;

  /// ESP32 uptime timestamp (millis).
  final int espTimestamp;

  /// Unique monotonic ID.
  final int id;
  static int _idCounter = 0;

  BugReport({
    required this.bug,
    required this.severity,
    required this.timestamp,
    required this.espTimestamp,
    this.state,
    this.level,
    this.details,
  }) : id = _idCounter++;

  /// Creates a [BugReport] from a decoded JSON map.
  factory BugReport.fromJson(Map<String, dynamic> json) {
    return BugReport(
      bug: (json['bug'] as String?) ?? 'UNKNOWN',
      severity: (json['severity'] as String?) ?? 'LOW',
      timestamp: DateTime.now(),
      espTimestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      state: json['state'] as String?,
      level: (json['level'] as num?)?.toInt(),
      details: json['details'] as String?,
    );
  }

  // ─── Severity Helpers ──────────────────────────────────────────

  bool get isLow => severity.toUpperCase() == 'LOW';
  bool get isMedium => severity.toUpperCase() == 'MEDIUM';
  bool get isHigh => severity.toUpperCase() == 'HIGH';
  bool get isCritical => severity.toUpperCase() == 'CRITICAL';

  /// Returns a numeric priority (higher = more severe).
  int get severityPriority {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return 4;
      case 'HIGH':
        return 3;
      case 'MEDIUM':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  // ─── Display Helpers ──────────────────────────────────────────

  /// Human-readable bug title.
  String get title => bug.replaceAll('_', ' ');

  /// Formatted timestamp as HH:MM:SS.mmm.
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Short formatted timestamp as HH:MM:SS.
  String get shortTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() =>
      'BugReport(bug=$bug, severity=$severity, level=$level, time=$formattedTimestamp)';
}
