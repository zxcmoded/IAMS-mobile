import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared brand chrome for every screen's [AppBar]: a diagonal gradient from
/// brand green into the metallic brand gray, bold white title text, and a
/// subtle drop shadow. Applied via this one widget (rather than
/// `AppBarTheme.backgroundColor`, which can only hold a solid [Color]) so the
/// look is consistent across screens without per-screen styling.
///
/// Drop-in replacement for `AppBar(...)` — every constructor parameter here
/// maps straight onto the wrapped [AppBar], so swapping `AppBar(` for
/// `GradientAppBar(` preserves existing `title`/`actions`/`leading` behavior
/// (including any `Key`s on those children) exactly.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final PreferredSizeWidget? bottom;

  /// Brand green -> metallic brand gray, same literal colors as the app's
  /// `ColorScheme.fromSeed` seed/secondary in `lib/app.dart`. Diagonal so the
  /// gradient reads clearly even on a short single-line AppBar.
  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E7D46), Color(0xFF7C8AA0)],
  );

  static const _elevation = 4.0;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      bottom: bottom,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      // Explicit shadowColor forces Material 3 to actually draw the
      // elevation shadow — by default M3 substitutes a surfaceTintColor
      // overlay instead, which would be invisible over a transparent
      // background.
      elevation: _elevation,
      scrolledUnderElevation: _elevation,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      // Light (white) status-bar icons/text stay readable against the dark
      // green end of the gradient, in both light and dark app theme.
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(gradient: _gradient),
      ),
    );
  }
}
