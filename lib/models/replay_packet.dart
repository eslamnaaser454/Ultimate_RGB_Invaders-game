/// A single recorded packet with timing metadata for replay.
///
/// [ReplayPacket] wraps any ESP32 packet (telemetry, event, bug,
/// diagnostics, assertion, testing, test_report) with a wall-clock
/// timestamp and a [relativeMs] offset from session start, enabling
/// accurate timed playback.
class ReplayPacket {
  /// The packet type string (e.g. "telemetry", "event", "bug").
  final String packetType;

  /// The full raw JSON payload from the ESP32.
  final Map<String, dynamic> payload;

  /// Wall-clock time the packet was captured.
  final DateTime timestamp;

  /// Milliseconds since session recording began.
  final int relativeMs;

  const ReplayPacket({
    required this.packetType,
    required this.payload,
    required this.timestamp,
    required this.relativeMs,
  });

  /// Serialize to a lightweight JSON-compatible map for storage.
  Map<String, dynamic> toJson() => {
        'packetType': packetType,
        'payload': payload,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'relativeMs': relativeMs,
      };

  /// Deserialize from stored JSON map.
  factory ReplayPacket.fromJson(Map<String, dynamic> json) {
    return ReplayPacket(
      packetType: json['packetType'] as String? ?? 'unknown',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
      relativeMs: json['relativeMs'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'ReplayPacket($packetType @ ${relativeMs}ms)';
}
