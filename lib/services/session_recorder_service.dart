import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/replay_packet.dart';
import '../models/replay_session.dart';

/// Records all incoming WebSocket packets into [ReplaySession]s.
///
/// Designed for lightweight, non-blocking operation:
/// - Packets are appended to a pre-allocated list
/// - No JSON encoding happens during recording (deferred to export)
/// - Rolling limit prevents unbounded memory growth
class SessionRecorderService {
  /// Maximum packets per session to prevent memory exhaustion.
  static const int maxPacketsPerSession = 50000;

  /// Maximum stored sessions in local storage.
  static const int maxStoredSessions = 20;

  ReplaySession? _currentSession;
  DateTime? _sessionStartTime;
  bool _isRecording = false;

  /// All completed sessions (in-memory cache).
  final List<ReplaySession> _sessions = [];

  // ─── State Getters ──────────────────────────────────────────────

  bool get isRecording => _isRecording;
  ReplaySession? get currentSession => _currentSession;
  List<ReplaySession> get sessions => List.unmodifiable(_sessions);
  int get currentPacketCount => _currentSession?.packetCount ?? 0;

  // ─── Recording Control ──────────────────────────────────────────

  /// Starts a new recording session.
  void startRecording() {
    if (_isRecording) return;
    _sessionStartTime = DateTime.now();
    _currentSession = ReplaySession(
      sessionId: 'session_${_sessionStartTime!.millisecondsSinceEpoch}',
      startTime: _sessionStartTime!,
    );
    _isRecording = true;
    debugPrint('[Recorder] Started session: ${_currentSession!.sessionId}');
  }

  /// Stops the current recording and archives the session.
  ReplaySession? stopRecording() {
    if (!_isRecording || _currentSession == null) return null;
    _isRecording = false;
    _currentSession!.endTime = DateTime.now();
    final session = _currentSession!;
    _sessions.insert(0, session);

    // Trim oldest sessions if over limit
    while (_sessions.length > maxStoredSessions) {
      _sessions.removeLast();
    }

    debugPrint(
        '[Recorder] Stopped. ${session.packetCount} packets in ${session.durationFormatted}');
    _currentSession = null;
    _sessionStartTime = null;
    return session;
  }

  /// Records a single parsed packet during an active session.
  void recordPacket(String packetType, Map<String, dynamic> payload) {
    if (!_isRecording || _currentSession == null) return;
    if (_currentSession!.packetCount >= maxPacketsPerSession) return;

    final now = DateTime.now();
    final relativeMs = now.difference(_sessionStartTime!).inMilliseconds;

    _currentSession!.packets.add(ReplayPacket(
      packetType: packetType,
      payload: Map<String, dynamic>.from(payload),
      timestamp: now,
      relativeMs: relativeMs,
    ));
  }

  // ─── Session Management ─────────────────────────────────────────

  /// Deletes a session by its ID.
  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.sessionId == sessionId);
  }

  /// Clears all stored sessions.
  void clearAll() {
    _sessions.clear();
  }

  // ─── Local Storage (SharedPreferences) ──────────────────────────

  /// Persists all sessions to SharedPreferences.
  Future<void> saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList =
          _sessions.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList('replay_sessions', jsonList);
      debugPrint('[Recorder] Saved ${jsonList.length} sessions to storage');
    } catch (e) {
      debugPrint('[Recorder] Save error: $e');
    }
  }

  /// Loads sessions from SharedPreferences.
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('replay_sessions') ?? [];
      _sessions.clear();
      for (final raw in jsonList) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _sessions.add(ReplaySession.fromJson(map));
      }
      debugPrint('[Recorder] Loaded ${_sessions.length} sessions from storage');
    } catch (e) {
      debugPrint('[Recorder] Load error: $e');
    }
  }

  /// Releases resources.
  void dispose() {
    _isRecording = false;
    _currentSession = null;
  }
}
