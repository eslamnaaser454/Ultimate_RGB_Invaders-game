import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_event.dart';
import '../utils/constants.dart';

/// Manages the event pipeline from raw JSON packets to typed [GameEvent] objects.
///
/// Responsibilities:
/// - Parse incoming event JSON packets
/// - Maintain a rolling buffer of [AppConstants.maxEventBuffer] events
/// - Broadcast events to listeners via stream
/// - Future-ready: replay engine, packet recording, analytics hooks
class EventService {
  /// Internal rolling event buffer (newest first).
  final List<GameEvent> _events = [];

  /// Broadcast stream controller for new events.
  final _eventController = StreamController<GameEvent>.broadcast();

  /// Broadcast stream controller for buffer changes (for bulk updates).
  final _bufferController = StreamController<List<GameEvent>>.broadcast();

  /// Stream of individual new events.
  Stream<GameEvent> get eventStream => _eventController.stream;

  /// Stream of the full buffer whenever it changes.
  Stream<List<GameEvent>> get bufferStream => _bufferController.stream;

  /// Current event buffer snapshot (newest first). Returns unmodifiable view.
  List<GameEvent> get events => List.unmodifiable(_events);

  /// Number of events currently in the buffer.
  int get eventCount => _events.length;

  /// The most recent event, or null if none.
  GameEvent? get latestEvent => _events.isNotEmpty ? _events.first : null;

  /// Total events ever processed (including those evicted from the buffer).
  int _totalProcessed = 0;
  int get totalProcessed => _totalProcessed;

  // ─── Future-Ready: Event Recording ──────────────────────────────
  List<Map<String, dynamic>>? _recordingBuffer;

  /// Whether event recording is active.
  bool get isRecording => _recordingBuffer != null;

  /// Starts recording all incoming event packets.
  void startRecording() => _recordingBuffer = [];

  /// Stops recording and returns the buffer of raw event maps.
  List<Map<String, dynamic>>? stopRecording() {
    final buffer = _recordingBuffer;
    _recordingBuffer = null;
    return buffer;
  }

  // ─── Core Processing ──────────────────────────────────────────

  /// Processes a raw JSON map that has been identified as an event packet.
  ///
  /// Parses the JSON into a [GameEvent], adds it to the rolling buffer,
  /// and notifies all listeners.
  void processEvent(Map<String, dynamic> json) {
    try {
      final event = GameEvent.fromJson(json);
      _addEvent(event);

      // Future-ready: record raw packet if recording
      if (_recordingBuffer != null) {
        _recordingBuffer!.add(json);
      }
    } catch (e) {
      debugPrint('[EventService] Failed to parse event: $e');
    }
  }

  /// Adds a [GameEvent] to the rolling buffer and notifies listeners.
  void _addEvent(GameEvent event) {
    // Insert at the front (newest first)
    _events.insert(0, event);
    _totalProcessed++;

    // Trim buffer to max size
    while (_events.length > AppConstants.maxEventBuffer) {
      _events.removeLast();
    }

    // Notify listeners
    _eventController.add(event);
    _bufferController.add(List.unmodifiable(_events));
  }

  // ─── Filtering ────────────────────────────────────────────────

  /// Returns events filtered by severity.
  List<GameEvent> filterBySeverity(String severity) {
    return _events
        .where((e) => e.severity.toLowerCase() == severity.toLowerCase())
        .toList();
  }

  /// Returns events filtered by category.
  List<GameEvent> filterByCategory(String category) {
    switch (category.toLowerCase()) {
      case 'boss':
        return _events.where((e) => e.isBossEvent).toList();
      case 'combo':
        return _events.where((e) => e.isComboEvent).toList();
      case 'system':
        return _events.where((e) => e.isSystemEvent).toList();
      case 'gameplay':
        return _events.where((e) => e.isGameplayEvent).toList();
      default:
        return List.unmodifiable(_events);
    }
  }

  // ─── Buffer Management ────────────────────────────────────────

  /// Clears all events from the buffer.
  void clearEvents() {
    _events.clear();
    _bufferController.add(const []);
  }

  // ─── Cleanup ──────────────────────────────────────────────────

  /// Releases all resources.
  void dispose() {
    _eventController.close();
    _bufferController.close();
    _events.clear();
  }
}
