import 'replay_packet.dart';

/// A complete recorded gameplay session containing all captured packets.
///
/// [ReplaySession] stores metadata about the session (duration, packet
/// counts by type) plus the full list of [ReplayPacket]s for playback.
class ReplaySession {
  /// Unique identifier for this session.
  final String sessionId;

  /// When recording started.
  final DateTime startTime;

  /// When recording stopped (null if still recording).
  DateTime? endTime;

  /// All captured packets in chronological order.
  final List<ReplayPacket> packets;

  ReplaySession({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    List<ReplayPacket>? packets,
  }) : packets = packets ?? [];

  // ─── Derived Metrics ────────────────────────────────────────────

  /// Total session duration in milliseconds.
  int get durationMs {
    if (packets.isEmpty) return 0;
    return packets.last.relativeMs;
  }

  /// Human-readable duration string.
  String get durationFormatted {
    final secs = durationMs ~/ 1000;
    final mins = secs ~/ 60;
    final remSecs = secs % 60;
    return '${mins.toString().padLeft(2, '0')}:${remSecs.toString().padLeft(2, '0')}';
  }

  int get packetCount => packets.length;

  int get telemetryCount =>
      packets.where((p) => p.packetType == 'telemetry').length;

  int get eventsCount =>
      packets.where((p) => p.packetType == 'event').length;

  int get diagnosticsCount =>
      packets.where((p) => p.packetType == 'diagnostics').length;

  int get bugsCount =>
      packets.where((p) => p.packetType == 'bug').length;

  int get assertionsCount =>
      packets.where((p) => p.packetType == 'assertion').length;

  int get testingCount =>
      packets.where((p) => p.packetType == 'testing').length;

  int get testReportsCount =>
      packets.where((p) => p.packetType == 'test_report').length;

  /// Average FPS extracted from telemetry packets (approximate).
  double get avgFps {
    final telPkts = packets.where((p) => p.packetType == 'diagnostics');
    if (telPkts.isEmpty) return 0;
    double sum = 0;
    int count = 0;
    for (final p in telPkts) {
      final fps = p.payload['fps'];
      if (fps is num) {
        sum += fps.toDouble();
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  /// Number of failed assertions in this session.
  int get failedAssertions => packets
      .where((p) =>
          p.packetType == 'assertion' && p.payload['result'] == 'FAILED')
      .length;

  // ─── Serialization ──────────────────────────────────────────────

  /// Serialize session metadata (without packets) for index display.
  Map<String, dynamic> toMetadata() => {
        'sessionId': sessionId,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime?.millisecondsSinceEpoch,
        'durationMs': durationMs,
        'packetCount': packetCount,
        'eventsCount': eventsCount,
        'bugsCount': bugsCount,
        'assertionsCount': assertionsCount,
      };

  /// Full serialization including all packets.
  Map<String, dynamic> toJson() => {
        ...toMetadata(),
        'packets': packets.map((p) => p.toJson()).toList(),
      };

  /// Deserialize from stored JSON.
  factory ReplaySession.fromJson(Map<String, dynamic> json) {
    final packetList = (json['packets'] as List?)
            ?.map((p) =>
                ReplayPacket.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList() ??
        [];
    return ReplaySession(
      sessionId: json['sessionId'] as String? ?? 'unknown',
      startTime: DateTime.fromMillisecondsSinceEpoch(
        json['startTime'] as int? ?? 0,
      ),
      endTime: json['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int)
          : null,
      packets: packetList,
    );
  }
}
