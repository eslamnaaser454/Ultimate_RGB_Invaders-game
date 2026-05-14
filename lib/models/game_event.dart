/// Data model representing a single gameplay event from the ESP32.
///
/// The ESP32 sends event packets over WebSocket with the following shape:
/// ```json
/// {
///   "type": "event",
///   "event": "BOSS_SPAWNED",
///   "timestamp": 123456,
///   "level": 10,
///   "severity": "info"
/// }
/// ```
///
/// Future-ready: supports payload for extended event data,
/// replay engine compatibility, and analytics hooks.
class GameEvent {
  /// Packet type identifier (always "event" for event packets).
  final String type;

  /// The event name (e.g. "BOSS_SPAWNED", "PLAYER_HIT").
  final String event;

  /// When the event was received by the dashboard.
  final DateTime timestamp;

  /// Event severity level: "info", "warning", or "error".
  final String severity;

  /// The game level at which the event occurred.
  final int level;

  /// Optional additional data associated with the event.
  final Map<String, dynamic>? payload;

  /// Unique ID for list key differentiation (monotonically increasing).
  final int id;

  /// Monotonic counter for unique event IDs.
  static int _idCounter = 0;

  GameEvent({
    required this.type,
    required this.event,
    required this.timestamp,
    required this.severity,
    required this.level,
    this.payload,
  }) : id = _idCounter++;

  /// Creates a [GameEvent] from a decoded JSON map.
  factory GameEvent.fromJson(Map<String, dynamic> json) {
    return GameEvent(
      type: (json['type'] as String?) ?? 'event',
      event: (json['event'] as String?) ?? 'UNKNOWN',
      timestamp: DateTime.now(),
      severity: (json['severity'] as String?) ?? 'info',
      level: (json['level'] as num?)?.toInt() ?? 0,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }

  // ─── Severity Helpers ──────────────────────────────────────────

  /// Whether this event is informational.
  bool get isInfo => severity.toLowerCase() == 'info';

  /// Whether this event is a warning.
  bool get isWarning => severity.toLowerCase() == 'warning';

  /// Whether this event is an error.
  bool get isError => severity.toLowerCase() == 'error';

  // ─── Event Category Helpers ────────────────────────────────────

  /// Whether this is a boss-related event.
  bool get isBossEvent =>
      event.startsWith('BOSS_') || event == 'BOSS_SEGMENT_DESTROYED';

  /// Whether this is a combo-related event.
  bool get isComboEvent => event.startsWith('COMBO_');

  /// Whether this is a gameplay/action event.
  bool get isGameplayEvent => const {
        'STATE_CHANGED',
        'LEVEL_COMPLETED',
        'GAME_OVER',
        'GAME_WON',
        'BASE_DESTROYED',
        'ENEMY_DESTROYED',
        'PLAYER_HIT',
        'PLAYER_DIED',
      }.contains(event);

  /// Whether this is a mini-game/system event.
  bool get isSystemEvent => const {
        'SIMON_STARTED',
        'SIMON_COMPLETED',
        'BEAT_SABER_STARTED',
        'BEAT_SABER_COMPLETED',
      }.contains(event);

  // ─── Category String ──────────────────────────────────────────

  /// Returns the event category as a human-readable string.
  String get category {
    if (isBossEvent) return 'Boss';
    if (isComboEvent) return 'Combo';
    if (isSystemEvent) return 'System';
    return 'Gameplay';
  }

  // ─── Display Helpers ──────────────────────────────────────────

  /// Human-readable event title.
  String get title {
    return event.replaceAll('_', ' ');
  }

  /// Formatted timestamp as HH:MM:SS.mmm
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Short formatted timestamp as HH:MM:SS
  String get shortTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() =>
      'GameEvent(event=$event, severity=$severity, level=$level, time=$formattedTimestamp)';
}
