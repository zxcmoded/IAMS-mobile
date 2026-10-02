import 'package:flutter/widgets.dart';

/// Publishes how much vertical space, in logical pixels, `MainShell`'s
/// floating "pill" bottom nav bar occupies — measured from the very bottom
/// of the screen up to the top edge of the pill (device safe-area inset +
/// the pill's own bottom margin + its height).
///
/// `MainShell` is the single source of truth for that footprint (it already
/// has to compute it to lay out `_ArtisticNavBar`); this widget just
/// republishes the number down the widget tree so any screen nested inside
/// the shell — most importantly ones with a `Scaffold.floatingActionButton`
/// — can pad itself clear of the bar without hardcoding the bar's height,
/// corner radius, or margins a second time.
///
/// Screens that are *not* nested inside `MainShell` (e.g. top-level routes
/// pushed over the whole shell) simply won't find this in their ancestry,
/// and [of] returns `0` — correct, since there's no floating bar to clear
/// there.
class NavBarReservedSpace extends InheritedWidget {
  const NavBarReservedSpace({
    super.key,
    required this.height,
    required super.child,
  });

  /// Distance from the bottom of the screen to the top of the floating nav
  /// bar. Already includes the device's bottom safe-area inset.
  final double height;

  /// Reads the nearest enclosing [NavBarReservedSpace]'s [height], or `0`
  /// when this context isn't nested inside `MainShell` at all.
  static double of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<NavBarReservedSpace>();
    return widget?.height ?? 0;
  }

  @override
  bool updateShouldNotify(NavBarReservedSpace oldWidget) =>
      height != oldWidget.height;
}
