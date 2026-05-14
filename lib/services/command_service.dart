import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/bot_status.dart';
import '../models/command_response.dart';

/// Phase 6: Manages command execution, bot control, and runtime interaction.
///
/// Handles three new packet types routed from WebSocket:
/// - `command_response` → ESP32 acknowledges/rejects a command
/// - `bot_status`       → autonomous bot state updates
/// - `input_action`     → input injection confirmations
///
/// Maintains command history, macro definitions, runtime parameter state,
/// bot status tracking, and safety system (cooldowns, rate limits).
class CommandService {
  // ─── Buffer Limits ─────────────────────────────────────────────
  static const int maxCommandHistory = 200;
  static const int maxResponseBuffer = 200;
  static const int maxPacketLog = 300;
  static const int _commandCooldownMs = 150;

  // ─── Internal State ────────────────────────────────────────────

  /// History of all sent commands (newest first).
  final List<CommandHistoryEntry> _commandHistory = [];

  /// Rolling buffer of incoming command responses (newest first).
  final List<CommandResponse> _responses = [];

  /// Live packet inspector log (newest first).
  final List<PacketLogEntry> _packetLog = [];

  /// Current bot status (latest update).
  BotStatus _botStatus = BotStatus.initial;

  /// Runtime parameters with current values and safe ranges.
  final Map<String, RuntimeParameter> _runtimeParams = {
    'bossSpeed': RuntimeParameter('Boss Speed', 1.0, 0.1, 5.0, 0.1),
    'enemySpawnRate': RuntimeParameter('Enemy Spawn Rate', 2.0, 0.5, 10.0, 0.5),
    'projectileSpeed': RuntimeParameter('Projectile Speed', 3.0, 0.5, 8.0, 0.5),
    'comboCooldown': RuntimeParameter('Combo Cooldown', 500, 50, 2000, 50),
    'stressIntensity': RuntimeParameter('Stress Intensity', 5, 1, 10, 1),
    'packetFloodIntensity':
        RuntimeParameter('Packet Flood Intensity', 3, 1, 10, 1),
  };

  /// Predefined macros.
  final Map<String, List<String>> _macros = {
    'boss_killer': [
      'start bot',
      'set bot_mode AGGRESSIVE',
      'set bot_target BOSS',
      'fire every 50ms',
    ],
    'stress_suite': [
      'run stress_test',
      'set stressIntensity 8',
      'set enemySpawnRate 8',
      'set projectileSpeed 6',
    ],
    'combo_spam': [
      'start bot',
      'set bot_mode PERFECT',
      'inject COMBO',
      'inject RAPID_FIRE',
    ],
    'projectile_chaos': [
      'set projectileSpeed 7',
      'set enemySpawnRate 9',
      'run stress_test',
    ],
    'rapid_fire_test': [
      'inject RAPID_FIRE',
      'inject FIRE',
      'inject FIRE',
      'inject FIRE',
    ],
  };

  /// Known command suggestions for autocomplete.
  static const List<String> knownCommands = [
    'spawn boss',
    'set level',
    'set score',
    'start bot',
    'stop bot',
    'set bot_mode',
    'set bot_target',
    'run stress_test',
    'restart game',
    'inject',
    'set bossSpeed',
    'set enemySpawnRate',
    'set projectileSpeed',
    'set comboCooldown',
    'set stressIntensity',
    'set packetFloodIntensity',
    'emergency_stop',
    'status',
    'ping',
  ];

  // ─── Safety System ─────────────────────────────────────────────

  DateTime? _lastCommandTime;
  int _commandsSentInWindow = 0;
  Timer? _rateWindowTimer;
  static const int _maxCommandsPerSecond = 10;

  /// Commands that require confirmation before sending.
  static const Set<String> dangerousCommands = {
    'restart game',
    'emergency_stop',
    'set stressIntensity',
    'set packetFloodIntensity',
  };

  // ─── Streams ───────────────────────────────────────────────────

  final _responseController = StreamController<CommandResponse>.broadcast();
  final _botStatusController = StreamController<BotStatus>.broadcast();
  final _packetLogController = StreamController<PacketLogEntry>.broadcast();

  Stream<CommandResponse> get responseStream => _responseController.stream;
  Stream<BotStatus> get botStatusStream => _botStatusController.stream;
  Stream<PacketLogEntry> get packetLogStream => _packetLogController.stream;

  // ─── Public Accessors ──────────────────────────────────────────

  List<CommandHistoryEntry> get commandHistory =>
      List.unmodifiable(_commandHistory);

  List<CommandResponse> get responses => List.unmodifiable(_responses);

  List<PacketLogEntry> get packetLog => List.unmodifiable(_packetLog);

  BotStatus get botStatus => _botStatus;

  Map<String, RuntimeParameter> get runtimeParams =>
      Map.unmodifiable(_runtimeParams);

  Map<String, List<String>> get macros => Map.unmodifiable(_macros);

  int get totalCommandsSent =>
      _commandHistory.where((e) => e.direction == 'OUT').length;

  int get totalResponses => _responses.length;

  int get successResponses => _responses.where((r) => r.isSuccess).length;

  int get errorResponses => _responses.where((r) => r.isError).length;

  // ─── Command Sending ──────────────────────────────────────────

  /// Validates and prepares a command for sending. Returns null if valid,
  /// or a warning message if the command is dangerous.
  String? validateCommand(String command) {
    if (command.trim().isEmpty) return 'Empty command';

    final lower = command.toLowerCase().trim();

    // Check cooldown
    if (_lastCommandTime != null) {
      final elapsed =
          DateTime.now().difference(_lastCommandTime!).inMilliseconds;
      if (elapsed < _commandCooldownMs) {
        return 'Command cooldown active (${_commandCooldownMs - elapsed}ms remaining)';
      }
    }

    // Check rate limit
    if (_commandsSentInWindow >= _maxCommandsPerSecond) {
      return 'Rate limit reached ($_maxCommandsPerSecond commands/sec)';
    }

    // Check dangerous commands
    for (final dangerous in dangerousCommands) {
      if (lower.startsWith(dangerous)) {
        return 'WARNING: "$command" is a dangerous command. Confirm to execute.';
      }
    }

    return null;
  }

  /// Builds the JSON payload for a command and returns it.
  String buildCommandPayload(String command) {
    return jsonEncode({
      'type': 'command',
      'command': command.trim(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Records a sent command in history and packet log.
  void recordSentCommand(String command) {
    final entry = CommandHistoryEntry(
      command: command.trim(),
      timestamp: DateTime.now(),
      direction: 'OUT',
      status: 'SENT',
    );

    _commandHistory.insert(0, entry);
    while (_commandHistory.length > maxCommandHistory) {
      _commandHistory.removeLast();
    }

    _logPacket('OUT', 'command', command.trim());

    // Rate limiting
    _lastCommandTime = DateTime.now();
    _commandsSentInWindow++;
    _rateWindowTimer?.cancel();
    _rateWindowTimer = Timer(const Duration(seconds: 1), () {
      _commandsSentInWindow = 0;
    });
  }

  /// Records an input injection action in history and packet log.
  String buildInputPayload(String action, {int duration = 100}) {
    return jsonEncode({
      'type': 'input_inject',
      'action': action,
      'duration': duration,
    });
  }

  /// Records an input injection in history.
  void recordInputInjection(String action, {int duration = 100}) {
    final entry = CommandHistoryEntry(
      command: 'inject $action (${duration}ms)',
      timestamp: DateTime.now(),
      direction: 'OUT',
      status: 'SENT',
    );

    _commandHistory.insert(0, entry);
    while (_commandHistory.length > maxCommandHistory) {
      _commandHistory.removeLast();
    }

    _logPacket('OUT', 'input_action', '$action (${duration}ms)');
  }

  // ─── Runtime Parameter Updates ─────────────────────────────────

  /// Builds the payload for a runtime parameter update.
  String buildParameterPayload(String paramKey, double value) {
    return jsonEncode({
      'type': 'set_param',
      'param': paramKey,
      'value': value,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Updates the local runtime parameter value.
  void updateLocalParameter(String key, double value) {
    final param = _runtimeParams[key];
    if (param != null) {
      _runtimeParams[key] = RuntimeParameter(
        param.label,
        value.clamp(param.min, param.max),
        param.min,
        param.max,
        param.step,
      );
    }
  }

  // ─── Packet Processing (from WebSocket routing) ────────────────

  /// Processes a `type: "command_response"` packet.
  void processCommandResponse(Map<String, dynamic> json) {
    try {
      final response = CommandResponse.fromJson(json);
      _responses.insert(0, response);

      while (_responses.length > maxResponseBuffer) {
        _responses.removeLast();
      }

      // Update matching command history entry
      for (int i = 0; i < _commandHistory.length; i++) {
        if (_commandHistory[i].command == response.command &&
            _commandHistory[i].status == 'SENT') {
          _commandHistory[i] = _commandHistory[i].withStatus(response.status);
          break;
        }
      }

      _logPacket('IN', 'command_response',
          '${response.command} → ${response.status}: ${response.message}');
      _responseController.add(response);
    } catch (e) {
      debugPrint('[CommandService] Failed to parse command_response: $e');
    }
  }

  /// Processes a `type: "bot_status"` packet.
  void processBotStatus(Map<String, dynamic> json) {
    try {
      final status = BotStatus.fromJson(json);
      _botStatus = status;

      _logPacket('IN', 'bot_status',
          '${status.botMode} | active=${status.active} | target=${status.target}');
      _botStatusController.add(status);
    } catch (e) {
      debugPrint('[CommandService] Failed to parse bot_status: $e');
    }
  }

  /// Processes a `type: "input_action"` echo/confirmation packet.
  void processInputAction(Map<String, dynamic> json) {
    try {
      final action = json['action'] as String? ?? 'UNKNOWN';
      final duration = json['duration'] as int? ?? 0;

      _logPacket('IN', 'input_action', '$action (${duration}ms) confirmed');
    } catch (e) {
      debugPrint('[CommandService] Failed to parse input_action: $e');
    }
  }

  // ─── Macro Execution ──────────────────────────────────────────

  /// Returns the command list for a macro name, or null if not found.
  List<String>? getMacroCommands(String macroName) => _macros[macroName];

  // ─── Script Parsing ────────────────────────────────────────────

  /// Parses a script string into individual commands.
  List<String> parseScript(String script) {
    return script
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  // ─── Autocomplete ──────────────────────────────────────────────

  /// Returns command suggestions matching the input prefix.
  List<String> getSuggestions(String input) {
    if (input.isEmpty) return knownCommands.take(8).toList();
    final lower = input.toLowerCase();
    return knownCommands
        .where((cmd) => cmd.toLowerCase().startsWith(lower))
        .take(6)
        .toList();
  }

  // ─── Packet Inspector ──────────────────────────────────────────

  void _logPacket(String direction, String type, String summary) {
    final entry = PacketLogEntry(
      direction: direction,
      type: type,
      summary: summary,
      timestamp: DateTime.now(),
    );
    _packetLog.insert(0, entry);
    while (_packetLog.length > maxPacketLog) {
      _packetLog.removeLast();
    }
    _packetLogController.add(entry);
  }

  // ─── Search & Filter ──────────────────────────────────────────

  /// Searches command history with optional filter.
  List<CommandHistoryEntry> searchHistory(String query,
      {String? statusFilter}) {
    return _commandHistory.where((entry) {
      final matchesQuery = query.isEmpty ||
          entry.command.toLowerCase().contains(query.toLowerCase());
      final matchesStatus =
          statusFilter == null || entry.status == statusFilter;
      return matchesQuery && matchesStatus;
    }).toList();
  }

  // ─── Bot Emergency Stop ────────────────────────────────────────

  /// Builds emergency stop payload.
  String buildEmergencyStopPayload() {
    return jsonEncode({
      'type': 'emergency_stop',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─── Buffer Management ─────────────────────────────────────────

  void clearHistory() {
    _commandHistory.clear();
  }

  void clearResponses() {
    _responses.clear();
  }

  void clearPacketLog() {
    _packetLog.clear();
  }

  void clearAll() {
    _commandHistory.clear();
    _responses.clear();
    _packetLog.clear();
    _botStatus = BotStatus.initial;
  }

  // ─── Cleanup ───────────────────────────────────────────────────

  void dispose() {
    _rateWindowTimer?.cancel();
    _responseController.close();
    _botStatusController.close();
    _packetLogController.close();
    _commandHistory.clear();
    _responses.clear();
    _packetLog.clear();
  }
}

// ─── Supporting Types ────────────────────────────────────────────

/// A single entry in the command history.
class CommandHistoryEntry {
  final String command;
  final DateTime timestamp;
  final String direction; // 'OUT' or 'IN'
  final String status; // 'SENT', 'SUCCESS', 'ERROR', 'FAIL', 'WARNING'

  const CommandHistoryEntry({
    required this.command,
    required this.timestamp,
    required this.direction,
    required this.status,
  });

  /// Returns a copy with updated status.
  CommandHistoryEntry withStatus(String newStatus) => CommandHistoryEntry(
        command: command,
        timestamp: timestamp,
        direction: direction,
        status: newStatus,
      );

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// An entry in the live packet inspector log.
class PacketLogEntry {
  final String direction; // 'IN' or 'OUT'
  final String type;
  final String summary;
  final DateTime timestamp;

  const PacketLogEntry({
    required this.direction,
    required this.type,
    required this.summary,
    required this.timestamp,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// A runtime-tunable parameter with safe range and step.
class RuntimeParameter {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;

  const RuntimeParameter(this.label, this.value, this.min, this.max, this.step);
}
