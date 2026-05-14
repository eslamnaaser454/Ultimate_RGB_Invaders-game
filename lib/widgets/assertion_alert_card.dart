import 'package:flutter/material.dart';

import '../models/assertion_result.dart';
import '../utils/constants.dart';

/// Cyberpunk-styled assertion alert card with severity-based glow.
class AssertionAlertCard extends StatelessWidget {
  final AssertionResult assertion;
  const AssertionAlertCard({super.key, required this.assertion});

  Color _severityColor() {
    if (assertion.isCritical) return AppConstants.neonRed;
    if (assertion.isHigh) return const Color(0xFFFF4444);
    if (assertion.isMedium) return AppConstants.neonOrange;
    return AppConstants.neonYellow;
  }

  Color _resultColor() {
    if (assertion.isPassed) return AppConstants.neonGreen;
    if (assertion.isFailed) return AppConstants.neonRed;
    return AppConstants.neonOrange;
  }

  IconData _resultIcon() {
    if (assertion.isPassed) return Icons.check_circle;
    if (assertion.isFailed) return Icons.cancel;
    return Icons.warning_amber;
  }

  @override
  Widget build(BuildContext context) {
    final sevColor = _severityColor();
    final resColor = _resultColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppConstants.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sevColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: sevColor.withValues(alpha: assertion.isFailed ? 0.15 : 0.05), blurRadius: 8),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(_resultIcon(), color: resColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(assertion.assertion, style: TextStyle(color: AppConstants.textPrimary, fontSize: 12, fontFamily: 'monospace', fontWeight: assertion.isFailed ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: sevColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text(assertion.severity, style: TextStyle(color: sevColor, fontSize: 9, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Text(assertion.formattedTime, style: const TextStyle(color: AppConstants.textDim, fontSize: 10)),
                ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: resColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(assertion.result, style: TextStyle(color: resColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
