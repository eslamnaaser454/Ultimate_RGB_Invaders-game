import 'package:flutter/material.dart';

import '../models/game_event.dart';
import '../utils/constants.dart';
import 'event_icons.dart';

/// A single event card in the timeline with cyberpunk neon styling.
///
/// Features:
/// - Severity-colored left border accent
/// - Event type icon with glow effect
/// - Formatted timestamp
/// - Expandable payload details
/// - Slide + fade insertion animation (handled by parent AnimatedList)
class EventTimelineCard extends StatefulWidget {
  final GameEvent event;
  final Animation<double> animation;

  const EventTimelineCard({
    super.key,
    required this.event,
    required this.animation,
  });

  @override
  State<EventTimelineCard> createState() => _EventTimelineCardState();
}

class _EventTimelineCardState extends State<EventTimelineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final severityColor = EventIcons.getSeverityColor(event.severity);
    final eventColor = EventIcons.getEventColor(event.event);
    final icon = EventIcons.getIcon(event.event);

    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: widget.animation,
          curve: Curves.easeIn,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.15, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: widget.animation,
            curve: Curves.easeOutCubic,
          )),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: event.payload != null
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: AppConstants.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: severityColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: severityColor.withValues(alpha: 0.06),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // ─── Severity Accent Bar ──────────────────
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: severityColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: severityColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                      ),

                      // ─── Content ─────────────────────────────
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Event icon with glow
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color:
                                          eventColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: eventColor
                                            .withValues(alpha: 0.25),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: eventColor
                                              .withValues(alpha: 0.15),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      icon,
                                      color: eventColor,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Event title + category
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.title,
                                          style: TextStyle(
                                            color: AppConstants.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            _CategoryTag(
                                                category: event.category,
                                                color: eventColor),
                                            const SizedBox(width: 6),
                                            Text(
                                              'LVL ${event.level}',
                                              style: TextStyle(
                                                color: AppConstants.textDim,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Timestamp + severity badge
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        event.shortTimestamp,
                                        style: TextStyle(
                                          color: AppConstants.textDim,
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _SeverityDot(severity: event.severity),
                                    ],
                                  ),
                                ],
                              ),

                              // Expandable payload
                              if (_expanded && event.payload != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppConstants.bgSurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppConstants.borderDim,
                                    ),
                                  ),
                                  child: Text(
                                    event.payload.toString(),
                                    style: TextStyle(
                                      color: AppConstants.textSecondary,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Expand indicator
                      if (event.payload != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: AppConstants.textDim,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Small Helper Widgets ────────────────────────────────────────

class _CategoryTag extends StatelessWidget {
  final String category;
  final Color color;

  const _CategoryTag({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        category.toUpperCase(),
        style: TextStyle(
          color: color.withValues(alpha: 0.8),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  final String severity;

  const _SeverityDot({required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = EventIcons.getSeverityColor(severity);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
