import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../providers/event_provider.dart';

/// A row of filter chips for the event timeline.
///
/// Provides both severity and category filtering with
/// a cyberpunk-styled chip appearance.
class EventFilterBar extends StatelessWidget {
  final SeverityFilter severityFilter;
  final CategoryFilter categoryFilter;
  final ValueChanged<SeverityFilter> onSeverityChanged;
  final ValueChanged<CategoryFilter> onCategoryChanged;
  final int totalCount;
  final int filteredCount;

  const EventFilterBar({
    super.key,
    required this.severityFilter,
    required this.categoryFilter,
    required this.onSeverityChanged,
    required this.onCategoryChanged,
    required this.totalCount,
    required this.filteredCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Severity Filters ──────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _FilterChip(
                label: 'ALL',
                selected: severityFilter == SeverityFilter.all,
                color: AppConstants.neonCyan,
                onTap: () => onSeverityChanged(SeverityFilter.all),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'INFO',
                selected: severityFilter == SeverityFilter.info,
                color: AppConstants.neonCyan,
                onTap: () => onSeverityChanged(SeverityFilter.info),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'WARNING',
                selected: severityFilter == SeverityFilter.warning,
                color: AppConstants.neonOrange,
                onTap: () => onSeverityChanged(SeverityFilter.warning),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'ERROR',
                selected: severityFilter == SeverityFilter.error,
                color: AppConstants.neonRed,
                onTap: () => onSeverityChanged(SeverityFilter.error),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ─── Category Filters ──────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _FilterChip(
                label: 'ALL',
                selected: categoryFilter == CategoryFilter.all,
                color: AppConstants.neonCyan,
                onTap: () => onCategoryChanged(CategoryFilter.all),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'GAMEPLAY',
                selected: categoryFilter == CategoryFilter.gameplay,
                color: AppConstants.neonGreen,
                icon: Icons.sports_esports_rounded,
                onTap: () => onCategoryChanged(CategoryFilter.gameplay),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'BOSS',
                selected: categoryFilter == CategoryFilter.boss,
                color: AppConstants.neonRed,
                icon: Icons.whatshot_rounded,
                onTap: () => onCategoryChanged(CategoryFilter.boss),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'COMBO',
                selected: categoryFilter == CategoryFilter.combo,
                color: AppConstants.neonYellow,
                icon: Icons.bolt_rounded,
                onTap: () => onCategoryChanged(CategoryFilter.combo),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'SYSTEM',
                selected: categoryFilter == CategoryFilter.system,
                color: AppConstants.neonMagenta,
                icon: Icons.memory_rounded,
                onTap: () => onCategoryChanged(CategoryFilter.system),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ─── Count indicator ───────────────────────────────────
        Text(
          filteredCount == totalCount
              ? '$totalCount events'
              : '$filteredCount / $totalCount events',
          style: TextStyle(
            color: AppConstants.textDim,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─── Filter Chip Widget ──────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.fastAnim,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppConstants.borderDim,
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: selected
                    ? color
                    : AppConstants.textDim,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppConstants.textDim,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
