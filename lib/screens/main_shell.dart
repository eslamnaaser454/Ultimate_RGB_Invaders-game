import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'automation_testing_screen.dart';
import 'bot_control_screen.dart';
import 'command_console_screen.dart';
import 'dashboard_screen.dart';
import 'diagnostics_screen.dart';
import 'replay_screen.dart';
import 'timeline_screen.dart';

/// Main navigation shell with bottom nav bar.
///
/// Phase 1: Dashboard tab is fully functional.
/// Tabs 2–4 (Timeline, Diagnostics, Testing) are placeholder stubs
/// that will be replaced in later phases.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // Pages are kept alive via IndexedStack for tab-state preservation
  final List<Widget> _pages = const [
    DashboardScreen(),
    TimelineScreen(),
    DiagnosticsScreen(),
    AutomationTestingScreen(),
    ReplayScreen(),
    CommandConsoleScreen(),
    BotControlScreen(),
  ];

  static const _navItems = <_NavItemData>[
    _NavItemData(icon: Icons.dashboard_rounded, label: 'DASH'),
    _NavItemData(icon: Icons.timeline_rounded, label: 'EVENTS'),
    _NavItemData(icon: Icons.analytics_rounded, label: 'DIAG'),
    _NavItemData(icon: Icons.science_rounded, label: 'TEST'),
    _NavItemData(icon: Icons.replay_circle_filled_rounded, label: 'REPLAY'),
    _NavItemData(icon: Icons.terminal_rounded, label: 'CMD'),
    _NavItemData(icon: Icons.smart_toy_rounded, label: 'BOT'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgPrimary,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _CyberpunkBottomNav(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─── Navigation Data ─────────────────────────────────────────────

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

// ─── Cyberpunk Bottom Nav ────────────────────────────────────────

class _CyberpunkBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<_NavItemData> items;
  final ValueChanged<int> onTap;

  const _CyberpunkBottomNav({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConstants.bottomNavHeight +
          MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: AppConstants.bottomNavBg,
        border: Border(
          top: BorderSide(
            color: AppConstants.neonCyan.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == currentIndex;
            return Expanded(
              child: _NavItem(
                data: items[i],
                selected: selected,
                onTap: () => onTap(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppConstants.neonCyan : AppConstants.textDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: AppConstants.bottomNavHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glow indicator line
            AnimatedContainer(
              duration: AppConstants.fastAnim,
              curve: Curves.easeOut,
              width: selected ? 28 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: selected ? AppConstants.neonCyan : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppConstants.neonCyan.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            ),
            // Icon
            AnimatedSwitcher(
              duration: AppConstants.fastAnim,
              child: Icon(
                data.icon,
                key: ValueKey('${data.label}_$selected'),
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            // Label
            Text(
              data.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

