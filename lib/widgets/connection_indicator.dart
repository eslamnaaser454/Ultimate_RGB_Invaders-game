import 'package:flutter/material.dart';

import '../services/websocket_service.dart' as ws;
import '../utils/constants.dart';

/// Animated connection status indicator with pulse animation.
class ConnectionIndicator extends StatefulWidget {
  final ws.ConnectionState state;
  final double telemetryRate;

  const ConnectionIndicator({
    super.key,
    required this.state,
    required this.telemetryRate,
  });

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(ConnectionIndicator old) {
    super.didUpdateWidget(old);
    _updatePulse();
  }

  void _updatePulse() {
    if (widget.state == ws.ConnectionState.connected) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _dotColor {
    switch (widget.state) {
      case ws.ConnectionState.connected:
        return AppConstants.neonGreen;
      case ws.ConnectionState.connecting:
        return AppConstants.neonYellow;
      case ws.ConnectionState.error:
        return AppConstants.neonRed;
      case ws.ConnectionState.disconnected:
        return AppConstants.textDim;
    }
  }

  String get _statusText {
    switch (widget.state) {
      case ws.ConnectionState.connected:
        return 'LIVE';
      case ws.ConnectionState.connecting:
        return 'Connecting...';
      case ws.ConnectionState.error:
        return 'Error';
      case ws.ConnectionState.disconnected:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _pulseAnim,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _dotColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _dotColor.withValues(alpha: 0.3 * _pulseAnim.value),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColor.withValues(alpha: _pulseAnim.value),
                  boxShadow: widget.state == ws.ConnectionState.connected
                      ? [
                          BoxShadow(
                            color: _dotColor.withValues(
                                alpha: 0.6 * _pulseAnim.value),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _statusText,
                style: TextStyle(
                  color: _dotColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              if (widget.state == ws.ConnectionState.connected &&
                  widget.telemetryRate > 0) ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 12,
                    color: _dotColor.withValues(alpha: 0.3)),
                const SizedBox(width: 6),
                Text(
                  '${widget.telemetryRate.toStringAsFixed(0)} Hz',
                  style: TextStyle(
                    color: _dotColor.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Reusable AnimatedWidget wrapper.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) => builder(context, child);
}
