import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_event.dart';
import '../providers/event_provider.dart';
import '../utils/constants.dart';
import '../widgets/event_filter_bar.dart';
import '../widgets/event_timeline_card.dart';

/// Realtime event timeline screen with animated insertions and filtering.
///
/// Features:
/// - AnimatedList for smooth event insertion
/// - Auto-scroll to newest events
/// - Severity and category filtering
/// - Event count and latest event display
/// - Cyberpunk debug terminal aesthetic
///
/// Performance:
/// - Uses AnimatedList (not ListView.builder) for O(1) insertions
/// - Selective rebuilds via Selector on event count + filter state
/// - Filter bar uses its own Selector to avoid full rebuilds
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final ScrollController _scrollController = ScrollController();

  /// Tracks how many events have been rendered into the AnimatedList.
  /// We compare against filteredEvents to detect new insertions.
  List<GameEvent> _displayedEvents = [];

  /// Subscription to the event provider for detecting new events.
  StreamSubscription<GameEvent>? _eventSub;

  /// Whether the user has scrolled away from the top (newest).
  bool _isAutoScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Defer subscription setup to after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initEventListener();
    });
  }

  void _initEventListener() {
    final provider = context.read<EventProvider>();

    // Initialize displayed events from current state
    _displayedEvents = List.from(provider.filteredEvents);

    // Listen for new events to insert into AnimatedList
    _eventSub = provider.service.eventStream.listen((_) {
      _syncAnimatedList();
    });
  }

  void _syncAnimatedList() {
    if (!mounted) return;

    final provider = context.read<EventProvider>();
    final filteredEvents = provider.filteredEvents;

    // Check for new events at the top (newest first)
    final newCount = filteredEvents.length - _displayedEvents.length;

    if (newCount > 0) {
      // Insert new events at position 0 (top)
      for (int i = 0; i < newCount; i++) {
        _listKey.currentState?.insertItem(
          0,
          duration: const Duration(milliseconds: 350),
        );
      }
      _displayedEvents = List.from(filteredEvents);

      // Auto-scroll to top if enabled
      if (_isAutoScrollEnabled && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } else if (newCount < 0 || filteredEvents.length != _displayedEvents.length) {
      // Filter changed — rebuild the entire list
      _rebuildList(filteredEvents);
    }
  }

  void _rebuildList(List<GameEvent> newEvents) {
    // Remove all current items
    for (int i = _displayedEvents.length - 1; i >= 0; i--) {
      _listKey.currentState?.removeItem(
        i,
        (context, animation) => const SizedBox.shrink(),
        duration: Duration.zero,
      );
    }

    _displayedEvents = List.from(newEvents);

    // Re-insert all items
    for (int i = 0; i < _displayedEvents.length; i++) {
      _listKey.currentState?.insertItem(
        i,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  void _onScroll() {
    // If user scrolls more than 50px from top, disable auto-scroll
    if (_scrollController.hasClients) {
      final atTop = _scrollController.offset < 50;
      if (_isAutoScrollEnabled != atTop) {
        setState(() => _isAutoScrollEnabled = atTop);
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: AppConstants.mediumAnim,
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _isAutoScrollEnabled = true);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────
            _TimelineHeader(),

            // ─── Filters ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenPadding,
              ),
              child: Consumer<EventProvider>(
                builder: (context, prov, _) {
                  return EventFilterBar(
                    severityFilter: prov.severityFilter,
                    categoryFilter: prov.categoryFilter,
                    onSeverityChanged: (filter) {
                      prov.setSeverityFilter(filter);
                      _rebuildList(prov.filteredEvents);
                    },
                    onCategoryChanged: (filter) {
                      prov.setCategoryFilter(filter);
                      _rebuildList(prov.filteredEvents);
                    },
                    totalCount: prov.eventCount,
                    filteredCount: prov.filteredEvents.length,
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // ─── Event List ──────────────────────────────────
            Expanded(
              child: Consumer<EventProvider>(
                builder: (context, prov, _) {
                  if (prov.eventCount == 0) {
                    return _EmptyState();
                  }

                  return AnimatedList(
                    key: _listKey,
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.screenPadding,
                    ),
                    initialItemCount: _displayedEvents.length,
                    itemBuilder: (context, index, animation) {
                      if (index >= _displayedEvents.length) {
                        return const SizedBox.shrink();
                      }
                      return EventTimelineCard(
                        key: ValueKey(_displayedEvents[index].id),
                        event: _displayedEvents[index],
                        animation: animation,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ─── Scroll-to-top FAB ────────────────────────────────
      floatingActionButton: _isAutoScrollEnabled
          ? null
          : FloatingActionButton.small(
              onPressed: _scrollToTop,
              backgroundColor: AppConstants.neonCyan.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: AppConstants.neonCyan.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                Icons.vertical_align_top_rounded,
                color: AppConstants.neonCyan,
                size: 20,
              ),
            ),
    );
  }
}

// ─── Timeline Header ────────────────────────────────────────────

class _TimelineHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          // Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EVENT TIMELINE',
                style: TextStyle(
                  color: AppConstants.neonCyan,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'REALTIME EVENTS',
                style: TextStyle(
                  color: AppConstants.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const Spacer(),

          // Latest event indicator
          Selector<EventProvider, GameEvent?>(
            selector: (_, p) => p.latestEvent,
            builder: (_, latestEvent, __) {
              if (latestEvent == null) return const SizedBox.shrink();
              return _LatestEventBadge(event: latestEvent);
            },
          ),

          const SizedBox(width: 8),

          // Clear button
          Consumer<EventProvider>(
            builder: (context, prov, _) {
              if (prov.eventCount == 0) return const SizedBox.shrink();
              return GestureDetector(
                onTap: prov.clearEvents,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppConstants.neonRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppConstants.neonRed.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.delete_sweep_rounded,
                    color: AppConstants.neonRed.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Latest Event Badge ─────────────────────────────────────────

class _LatestEventBadge extends StatelessWidget {
  final GameEvent event;

  const _LatestEventBadge({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.neonGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppConstants.neonGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConstants.neonGreen,
              boxShadow: [
                BoxShadow(
                  color: AppConstants.neonGreen.withValues(alpha: 0.6),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: AppConstants.neonGreen,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConstants.neonCyan.withValues(alpha: 0.06),
              border: Border.all(
                color: AppConstants.neonCyan.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              Icons.timeline_rounded,
              color: AppConstants.neonCyan.withValues(alpha: 0.4),
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'NO EVENTS YET',
            style: TextStyle(
              color: AppConstants.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gameplay events will appear here in realtime',
            style: TextStyle(
              color: AppConstants.textDim.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
