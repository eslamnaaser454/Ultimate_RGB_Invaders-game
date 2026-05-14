/// Data model representing a diagnostics snapshot from the ESP32.
///
/// The ESP32 sends diagnostics packets every 500ms:
/// ```json
/// {
///   "type": "diagnostics",
///   "timestamp": 123456,
///   "fps": 58,
///   "frameTime": 16,
///   "heap": 182000,
///   "minHeap": 160000,
///   "wifiRssi": -52,
///   "latency": 12,
///   "packetRate": 10,
///   "telemetryHealth": 98,
///   "wsClients": 1,
///   "packetsSent": 500,
///   "sendFails": 0,
///   "assertions": 0,
///   "tasks": [...]
/// }
/// ```
class DiagnosticsData {
  /// Current FPS of the game loop.
  final double fps;

  /// Frame time in milliseconds.
  final double frameTime;

  /// Current free heap in bytes.
  final int heap;

  /// Minimum free heap since boot (watermark).
  final int minHeap;

  /// WiFi RSSI (signal strength, dBm). Closer to 0 = better.
  final int wifiRssi;

  /// WebSocket round-trip latency in ms.
  final double latency;

  /// Packets sent per second by the ESP32.
  final int packetRate;

  /// Telemetry health percentage (0–100).
  final int telemetryHealth;

  /// Number of connected WebSocket clients.
  final int wsClients;

  /// Total telemetry packets sent since boot.
  final int packetsSent;

  /// Total send failures since boot.
  final int sendFails;

  /// Total assertion failures detected.
  final int assertions;

  /// ESP32 uptime timestamp (millis).
  final int espTimestamp;

  /// When the dashboard received this snapshot.
  final DateTime receivedAt;

  const DiagnosticsData({
    required this.fps,
    required this.frameTime,
    required this.heap,
    required this.minHeap,
    required this.wifiRssi,
    required this.latency,
    required this.packetRate,
    required this.telemetryHealth,
    required this.wsClients,
    required this.packetsSent,
    required this.sendFails,
    required this.assertions,
    required this.espTimestamp,
    required this.receivedAt,
  });

  /// Creates a [DiagnosticsData] from a decoded JSON map.
  factory DiagnosticsData.fromJson(Map<String, dynamic> json) {
    return DiagnosticsData(
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      frameTime: (json['frameTime'] as num?)?.toDouble() ?? 0,
      heap: (json['heap'] as num?)?.toInt() ?? 0,
      minHeap: (json['minHeap'] as num?)?.toInt() ?? 0,
      wifiRssi: (json['wifiRssi'] as num?)?.toInt() ?? 0,
      latency: (json['latency'] as num?)?.toDouble() ?? 0,
      packetRate: (json['packetRate'] as num?)?.toInt() ?? 0,
      telemetryHealth: (json['telemetryHealth'] as num?)?.toInt() ?? 100,
      wsClients: (json['wsClients'] as num?)?.toInt() ?? 0,
      packetsSent: (json['packetsSent'] as num?)?.toInt() ?? 0,
      sendFails: (json['sendFails'] as num?)?.toInt() ?? 0,
      assertions: (json['assertions'] as num?)?.toInt() ?? 0,
      espTimestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      receivedAt: DateTime.now(),
    );
  }

  /// Default empty state.
  static DiagnosticsData get empty => DiagnosticsData(
        fps: 0,
        frameTime: 0,
        heap: 0,
        minHeap: 0,
        wifiRssi: 0,
        latency: 0,
        packetRate: 0,
        telemetryHealth: 100,
        wsClients: 0,
        packetsSent: 0,
        sendFails: 0,
        assertions: 0,
        espTimestamp: 0,
        receivedAt: DateTime.now(),
      );

  // ─── Health Helpers ──────────────────────────────────────────

  /// Heap usage percentage (assuming 320KB total SRAM on ESP32-S3).
  double get heapUsagePercent {
    const totalSram = 327680; // 320KB
    if (heap <= 0) return 0;
    return ((totalSram - heap) / totalSram * 100).clamp(0, 100);
  }

  /// WiFi signal quality string.
  String get wifiQuality {
    if (wifiRssi >= -50) return 'Excellent';
    if (wifiRssi >= -60) return 'Good';
    if (wifiRssi >= -70) return 'Fair';
    if (wifiRssi >= -80) return 'Weak';
    return 'Very Weak';
  }

  /// Whether FPS indicates performance issues.
  bool get isFpsLow => fps > 0 && fps < 30;

  /// Whether heap is critically low (< 40KB free).
  bool get isHeapCritical => heap > 0 && heap < 40000;

  /// Whether there are send failures.
  bool get hasSendFailures => sendFails > 0;

  /// Send success rate percentage.
  double get sendSuccessRate {
    final total = packetsSent;
    if (total <= 0) return 100;
    return ((total - sendFails) / total * 100).clamp(0, 100);
  }

  @override
  String toString() =>
      'DiagnosticsData(fps=$fps, heap=$heap, rssi=$wifiRssi, health=$telemetryHealth)';
}
