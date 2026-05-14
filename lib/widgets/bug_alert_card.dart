import 'package:flutter/material.dart';

import '../models/bug_report.dart';
import '../utils/constants.dart';

/// An animated cyberpunk-styled card displaying a single bug alert.
///
/// Features:
/// - Severity-based glow colors (yellow → red → flashing red)
/// - Animated appearance
/// - Expandable details section
/// - Timestamp + state context
class BugAlertCard extends StatefulWidget {
  final BugReport bug;
  final int index;

  const BugAlertCard({super.key, required this.bug, required this.index});

  @override
  State<BugAlertCard> createState() => _BugAlertCardState();
}

class _BugAlertCardState extends State<BugAlertCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final delay = (widget.index * 0.08).clamp(0.0, 0.5);
    _slideAnim = Tween<double>(begin: 30, end: 0).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    ));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Interval(delay, 1.0, curve: Curves.easeOut),
    ));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Color _severityColor() {
    switch (widget.bug.severity.toUpperCase()) {
      case 'CRITICAL':
        return AppConstants.neonRed;
      case 'HIGH':
        return const Color(0xFFFF4444);
      case 'MEDIUM':
        return AppConstants.neonOrange;
      case 'LOW':
        return AppConstants.neonYellow;
      default:
        return AppConstants.textDim;
    }
  }

  IconData _severityIcon() {
    switch (widget.bug.severity.toUpperCase()) {
      case 'CRITICAL':
        return Icons.error;
      case 'HIGH':
        return Icons.warning_amber_rounded;
      case 'MEDIUM':
        return Icons.info_outline;
      case 'LOW':
        return Icons.bug_report_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();
    final bug = widget.bug;

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: Opacity(opacity: _fadeAnim.value, child: child),
        );
      },
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(_severityIcon(), color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bug.title,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Severity badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      bug.severity.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Meta row
              Row(
                children: [
                  Icon(Icons.access_time,
                      color: AppConstants.textDim, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    bug.shortTimestamp,
                    style: TextStyle(
                      color: AppConstants.textDim,
                      fontSize: 11,
                    ),
                  ),
                  if (bug.state != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.gamepad_outlined,
                        color: AppConstants.textDim, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      bug.state!,
                      style: TextStyle(
                        color: AppConstants.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (bug.level != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'LVL ${bug.level}',
                      style: TextStyle(
                        color: AppConstants.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppConstants.textDim,
                    size: 16,
                  ),
                ],
              ),

              // Expanded details
              if (_expanded && bug.details != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppConstants.bgPrimary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppConstants.borderDim.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    bug.details!,
                    style: TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
