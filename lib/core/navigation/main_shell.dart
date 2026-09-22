import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Persistent bottom navigation shell for the 4 primary tabs: Home,
/// Inventory, Audit, Settings.
///
/// Wraps the [StatefulNavigationShell] produced by
/// `StatefulShellRoute.indexedStack` in `app_router.dart` — each tab keeps
/// its own navigation state (scroll position, in-progress forms, etc.) when
/// the user switches away and back, since the shell holds every branch alive
/// in an `IndexedStack` rather than rebuilding on tab switch.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  /// Provided by `StatefulShellRoute.indexedStack`'s builder.
  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // Re-tapping the already-selected tab pops that tab's stack back to
      // its root, matching standard bottom-nav behavior.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: _ArtisticNavBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          _NavDestinationData(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
          ),
          _NavDestinationData(
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            label: 'Inventory',
          ),
          _NavDestinationData(
            icon: Icons.fact_check_outlined,
            selectedIcon: Icons.fact_check,
            label: 'Audit',
          ),
          _NavDestinationData(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Plain-data description of a single tab, analogous to what
/// [NavigationDestination] carried before this widget replaced it.
class _NavDestinationData {
  const _NavDestinationData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating "dock" style bottom navigation bar.
///
/// Visual replacement for the stock Material [NavigationBar] — same
/// selection/tap semantics (driven entirely by [selectedIndex] and
/// [onDestinationSelected]), but rendered as a frosted, rounded, floating
/// pill with an animated selection indicator instead of a flush Material 3
/// bar. Built entirely from core Flutter widgets (no new dependencies).
class _ArtisticNavBar extends StatelessWidget {
  const _ArtisticNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_NavDestinationData> destinations;

  static const double _barHeight = 64;
  static const double _cornerRadius = 28;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cornerRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: _barHeight,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(_cornerRadius),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / destinations.length;
                return Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(
                        // Map tab index -> [-1, 1] horizontal alignment for
                        // the width of a single tab's indicator pill.
                        destinations.length == 1
                            ? 0
                            : -1 +
                                (2 * selectedIndex) /
                                    (destinations.length - 1),
                        0,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Container(
                          width: tabWidth - 12,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(
                              _cornerRadius - 8,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          SizedBox(
                            width: tabWidth,
                            child: _NavTab(
                              data: destinations[i],
                              selected: i == selectedIndex,
                              onTap: () => onDestinationSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Single tappable tab within [_ArtisticNavBar]: icon (outlined when
/// unselected, filled + scaled-up when selected) with an always-visible
/// label underneath.
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _NavDestinationData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: iconColor,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );

    return Semantics(
      label: data.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: data.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      selected ? data.selectedIcon : data.icon,
                      color: iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.label,
                    style: labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
