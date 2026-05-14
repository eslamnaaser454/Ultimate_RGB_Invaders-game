/// Data model representing a single telemetry packet from the ESP32.
///
/// The ESP32 sends JSON objects over WebSocket with the following shape:
/// ```json
/// {
///   "level": 10,
///   "score": 124000,
///   "bossHP": 23,
///   "maxBossHP": 45,
///   "enemies": 7,
///   "state": "BOSS",
///   "projectiles": 4,
///   "accuracy": 89,
///   "comboColor": 6,
///   "mode": "FINAL_BOSS",
///   "simonStage": 0,
///   "beatSaber": false,
///   "leds": [0,0,1,1,2,3,4,5,6,7]
/// }
/// ```
class TelemetryData {
  final int level;
  final int score;
  final int bossHP;
  final int maxBossHP;
  final int enemies;
  final String state;
  final int projectiles;
  final int accuracy;
  final int comboColor;
  final String mode;
  final int simonStage;
  final bool beatSaber;
  final List<int> leds;
  final DateTime receivedAt;

  const TelemetryData({
    required this.level,
    required this.score,
    required this.bossHP,
    required this.maxBossHP,
    required this.enemies,
    required this.state,
    required this.projectiles,
    required this.accuracy,
    required this.comboColor,
    required this.mode,
    required this.simonStage,
    required this.beatSaber,
    required this.leds,
    required this.receivedAt,
  });

  /// Creates a [TelemetryData] from a decoded JSON map.
  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      level: (json['level'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      bossHP: (json['bossHP'] as num?)?.toInt() ?? 0,
      maxBossHP: (json['maxBossHP'] as num?)?.toInt() ?? 1,
      enemies: (json['enemies'] as num?)?.toInt() ?? 0,
      state: (json['state'] as String?) ?? 'IDLE',
      projectiles: (json['projectiles'] as num?)?.toInt() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toInt() ?? 0,
      comboColor: (json['comboColor'] as num?)?.toInt() ?? 0,
      mode: (json['mode'] as String?) ?? 'NORMAL',
      simonStage: (json['simonStage'] as num?)?.toInt() ?? 0,
      beatSaber: (json['beatSaber'] as bool?) ?? false,
      leds: (json['leds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      receivedAt: DateTime.now(),
    );
  }

  /// Returns the boss HP as a ratio between 0.0 and 1.0.
  double get bossHPRatio =>
      maxBossHP > 0 ? (bossHP / maxBossHP).clamp(0.0, 1.0) : 0.0;

  /// Whether the boss fight is currently active.
  bool get isBossFight =>
      state.toUpperCase() == 'BOSS' || mode.toUpperCase() == 'FINAL_BOSS';

  /// A default/empty state used before any data arrives.
  static TelemetryData get empty => TelemetryData(
        level: 0,
        score: 0,
        bossHP: 0,
        maxBossHP: 1,
        enemies: 0,
        state: 'IDLE',
        projectiles: 0,
        accuracy: 0,
        comboColor: 0,
        mode: 'NORMAL',
        simonStage: 0,
        beatSaber: false,
        leds: [],
        receivedAt: DateTime.now(),
      );

  @override
  String toString() =>
      'TelemetryData(level=$level, score=$score, state=$state, mode=$mode)';
}
