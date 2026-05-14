import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game_event.dart';
import '../services/event_service.dart';

/// Severity filter options for the timeline.
enum SeverityFilter { all, info, warning, error }

/// Category filter options for the timeline.
enum CategoryFilter { all, gameplay, boss, combo, system }

/// Provides event state to the widget tree via [ChangeNotifier].
///
/// Wraps [EventService], exposes filtered and unfiltered event lists,
/// the latest event, filter controls, and event counts.
///
/// Performance: uses selective notifyListeners and exposes
/// data for [Selector] widgets to minimize rebuilds.
class EventProvider extends ChangeNotifier {
  final EventService _service;

  StreamSubscription<GameEvent>? _eventSub;
  StreamSubscription<List<GameEvent>>? _bufferSub;

  /// Current filter states.
  SeverityFilter _severityFilter = SeverityFilter.all;
  CategoryFilter _categoryFilter = CategoryFilter.all;

  /// Cached filtered list to avoid recomputation on every access.
  List<GameEvent> _filteredEvents = [];
  bool _filterDirty = true;

  EventProvider() : _service = EventService() {
    _listen();
  }

  /// Creates an EventProvider using an external [EventService] instance.
  /// Used to share the same EventService that's wired to WebSocket routing.
  EventProvider.withService(EventService service) : _service = service {
    _listen();
  }

  void _listen() {
    _eventSub?.cancel();
    _eventSub = _service.eventStream.listen((_) {
      _filterDirty = true;
      notifyListeners();
    });
  }

  // ─── Service Access ───────────────────────────────────────────

  /// The underlying event service (for WebSocket integration).
  EventService get service => _service;

  // ─── Getters ──────────────────────────────────────────────────

  /// All events in the buffer (newest first).
  List<GameEvent> get allEvents => _service.events;

  /// The most recent event, or null.
  GameEvent? get latestEvent => _service.latestEvent;

  /// Number of events in the buffer.
  int get eventCount => _service.eventCount;

  /// Total events ever processed.
  int get totalProcessed => _service.totalProcessed;

  /// Current severity filter.
  SeverityFilter get severityFilter => _severityFilter;

  /// Current category filter.
  CategoryFilter get categoryFilter => _categoryFilter;

  /// Returns the filtered events based on current filter settings.
  /// Caches the result to avoid recomputation.
  List<GameEvent> get filteredEvents {
    if (_filterDirty) {
      _recomputeFilter();
      _filterDirty = false;
    }
    return _filteredEvents;
  }

  // ─── Filter Controls ──────────────────────────────────────────

  /// Sets the severity filter and triggers a rebuild.
  void setSeverityFilter(SeverityFilter filter) {
    if (_severityFilter == filter) return;
    _severityFilter = filter;
    _filterDirty = true;
    notifyListeners();
  }

  /// Sets the category filter and triggers a rebuild.
  void setCategoryFilter(CategoryFilter filter) {
    if (_categoryFilter == filter) return;
    _categoryFilter = filter;
    _filterDirty = true;
    notifyListeners();
  }

  /// Clears all filters back to "all".
  void clearFilters() {
    _severityFilter = SeverityFilter.all;
    _categoryFilter = CategoryFilter.all;
    _filterDirty = true;
    notifyListeners();
  }

  /// Clears the event buffer.
  void clearEvents() {
    _service.clearEvents();
    _filterDirty = true;
    notifyListeners();
  }

  // ─── Filter Logic ─────────────────────────────────────────────

  void _recomputeFilter() {
    var events = _service.events;

    // Apply severity filter
    if (_severityFilter != SeverityFilter.all) {
      final severity = _severityFilter.name;
      events = events
          .where((e) => e.severity.toLowerCase() == severity)
          .toList();
    }

    // Apply category filter
    if (_categoryFilter != CategoryFilter.all) {
      switch (_categoryFilter) {
        case CategoryFilter.boss:
          events = events.where((e) => e.isBossEvent).toList();
          break;
        case CategoryFilter.combo:
          events = events.where((e) => e.isComboEvent).toList();
          break;
        case CategoryFilter.system:
          events = events.where((e) => e.isSystemEvent).toList();
          break;
        case CategoryFilter.gameplay:
          events = events.where((e) => e.isGameplayEvent).toList();
          break;
        case CategoryFilter.all:
          break;
      }
    }

    _filteredEvents = events;
  }

  // ─── Cleanup ──────────────────────────────────────────────────

  @override
  void dispose() {
    _eventSub?.cancel();
    _bufferSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
