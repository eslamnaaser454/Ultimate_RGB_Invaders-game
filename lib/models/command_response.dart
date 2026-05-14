/// Phase 6: Command response packet model.
///
/// Represents a response from the ESP32 to a command sent from the dashboard.
///
/// Example JSON:
/// ```json
/// {
///   "type":"command_response",
///   "timestamp":123456,
///   "command":"spawn boss",
///   "status":"SUCCESS",
///   "message":"Boss spawned successfully"
/// }
/// ```
class CommandResponse {
  final int timestamp;
  final String command;
  final String status;
  final String message;
  final DateTime receivedAt;

  const CommandResponse({
    required this.timestamp,
    required this.command,
    required this.status,
    required this.message,
    required this.receivedAt,
  });

  factory CommandResponse.fromJson(Map<String, dynamic> json) {
    return CommandResponse(
      timestamp: json['timestamp'] as int? ?? 0,
      command: json['command'] as String? ?? '',
      status: json['status'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? '',
      receivedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'command_response',
        'timestamp': timestamp,
        'command': command,
        'status': status,
        'message': message,
      };

  bool get isSuccess => status == 'SUCCESS';
  bool get isError => status == 'ERROR' || status == 'FAIL';
  bool get isWarning => status == 'WARNING';

  String get formattedTime {
    final h = receivedAt.hour.toString().padLeft(2, '0');
    final m = receivedAt.minute.toString().padLeft(2, '0');
    final s = receivedAt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
