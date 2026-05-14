/// Phase 6: Bot status packet model.
///
/// Represents the current state and performance of the autonomous gameplay bot.
///
/// Example JSON:
/// ```json
/// {
///   "type":"bot_status",
///   "timestamp":123456,
///   "botMode":"AGGRESSIVE",
///   "active":true,
///   "target":"BOSS",
///   "accuracy":92,
///   "dodgeRate":88
/// }
/// ```
class BotStatus {
  final int timestamp;
  final String botMode;
  final bool active;
  final String target;
  final int accuracy;
  final int dodgeRate;
  final int comboRate;
  final List<String> activeActions;
  final DateTime receivedAt;

  BotStatus({
    required this.timestamp,
    required this.botMode,
    required this.active,
    required this.target,
    required this.accuracy,
    required this.dodgeRate,
    required this.comboRate,
    required this.activeActions,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory BotStatus.fromJson(Map<String, dynamic> json) {
    return BotStatus(
      timestamp: json['timestamp'] as int? ?? 0,
      botMode: json['botMode'] as String? ?? 'UNKNOWN',
      active: json['active'] as bool? ?? false,
      target: json['target'] as String? ?? 'NONE',
      accuracy: json['accuracy'] as int? ?? 0,
      dodgeRate: json['dodgeRate'] as int? ?? 0,
      comboRate: json['comboRate'] as int? ?? 0,
      activeActions: (json['activeActions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'bot_status',
        'timestamp': timestamp,
        'botMode': botMode,
        'active': active,
        'target': target,
        'accuracy': accuracy,
        'dodgeRate': dodgeRate,
        'comboRate': comboRate,
        'activeActions': activeActions,
      };

  /// Default / initial bot status.
  static BotStatus get initial => BotStatus(
        timestamp: 0,
        botMode: 'NONE',
        active: false,
        target: 'NONE',
        accuracy: 0,
        dodgeRate: 0,
        comboRate: 0,
        activeActions: [],
      );

  String get formattedTime {
    final h = receivedAt.hour.toString().padLeft(2, '0');
    final m = receivedAt.minute.toString().padLeft(2, '0');
    final s = receivedAt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
