import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bot_status.dart';
import '../models/command_response.dart';
import '../services/command_service.dart';

/// Phase 6: Provides command console & bot control state to the widget tree.
///
/// Wraps [CommandService] and uses a throttled notification model (200ms)
/// consistent with existing providers to prevent excessive rebuilds
/// from high-frequency command response and bot status packets.
class CommandProvider extends ChangeNotifier {
  CommandService _service;

  StreamSubscription<CommandResponse>? _responseSub;
  StreamSubscription<BotStatus>? _botStatusSub;
  StreamSubscription<PacketLogEntry>? _packetLogSub;

  // UI throttle — max ~5 rebuilds/sec (200ms).
  static const int _throttleMs = 200;
  bool _pendingNotify = false;
  Timer? _throttleTimer;

  CommandProvider() : _service = CommandService() {
    _listen();
  }

  /// Creates a provider using an externally-provided service (for sharing
  /// the same instance wired to WebSocket routing).
  CommandProvider.withService(CommandService service) : _service = service {
    _listen();
  }

  void _listen() {
    _responseSub?.cancel();
    _botStatusSub?.cancel();
    _packetLogSub?.cancel();

    _responseSub = _service.responseStream.listen((_) => _scheduleNotify());
    _botStatusSub = _service.botStatusStream.listen((_) => _scheduleNotify());
    _packetLogSub = _service.packetLogStream.listen((_) => _scheduleNotify());
  }

  /// Replaces the underlying service (used by ProxyProvider updates).
  void updateService(CommandService service) {
    if (_service == service) return;
    _service = service;
    _listen();
    notifyListeners();
  }

  void _scheduleNotify() {
    if (_pendingNotify) return;
    _pendingNotify = true;
    _throttleTimer?.cancel();
    _throttleTimer = Timer(const Duration(milliseconds: _throttleMs), () {
      _pendingNotify = false;
      notifyListeners();
    });
  }

  // ─── Service Access ──────────────────────────────────────────

  CommandService get service => _service;

  // ─── Command Accessors ───────────────────────────────────────

  List<CommandHistoryEntry> get commandHistory => _service.commandHistory;
  List<CommandResponse> get responses => _service.responses;
  List<PacketLogEntry> get packetLog => _service.packetLog;
  BotStatus get botStatus => _service.botStatus;

  Map<String, RuntimeParameter> get runtimeParams => _service.runtimeParams;
  Map<String, List<String>> get macros => _service.macros;

  int get totalCommandsSent => _service.totalCommandsSent;
  int get totalResponses => _service.totalResponses;
  int get successResponses => _service.successResponses;
  int get errorResponses => _service.errorResponses;

  // ─── Command Actions ─────────────────────────────────────────

  /// Validates a command. Returns null if valid, or a message if invalid.
  String? validateCommand(String command) => _service.validateCommand(command);

  /// Builds command payload JSON string.
  String buildCommandPayload(String command) =>
      _service.buildCommandPayload(command);

  /// Records a sent command in history.
  void recordSentCommand(String command) {
    _service.recordSentCommand(command);
    notifyListeners();
  }

  /// Builds input injection payload JSON string.
  String buildInputPayload(String action, {int duration = 100}) =>
      _service.buildInputPayload(action, duration: duration);

  /// Records an input injection in history.
  void recordInputInjection(String action, {int duration = 100}) {
    _service.recordInputInjection(action, duration: duration);
    notifyListeners();
  }

  /// Updates a runtime parameter locally.
  void updateLocalParameter(String key, double value) {
    _service.updateLocalParameter(key, value);
    notifyListeners();
  }

  /// Builds runtime parameter payload JSON string.
  String buildParameterPayload(String paramKey, double value) =>
      _service.buildParameterPayload(paramKey, value);

  /// Gets command suggestions.
  List<String> getSuggestions(String input) => _service.getSuggestions(input);

  /// Gets macro commands.
  List<String>? getMacroCommands(String macroName) =>
      _service.getMacroCommands(macroName);

  /// Parses a script into commands.
  List<String> parseScript(String script) => _service.parseScript(script);

  /// Searches command history.
  List<CommandHistoryEntry> searchHistory(String query,
          {String? statusFilter}) =>
      _service.searchHistory(query, statusFilter: statusFilter);

  /// Builds emergency stop payload.
  String buildEmergencyStopPayload() => _service.buildEmergencyStopPayload();

  // ─── Buffer Management ───────────────────────────────────────

  void clearHistory() {
    _service.clearHistory();
    notifyListeners();
  }

  void clearResponses() {
    _service.clearResponses();
    notifyListeners();
  }

  void clearPacketLog() {
    _service.clearPacketLog();
    notifyListeners();
  }

  void clearAll() {
    _service.clearAll();
    notifyListeners();
  }

  // ─── Cleanup ─────────────────────────────────────────────────

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _responseSub?.cancel();
    _botStatusSub?.cancel();
    _packetLogSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
