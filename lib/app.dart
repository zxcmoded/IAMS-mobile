import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
import 'features/access/presentation/controller/selected_location_controller.dart';
import 'features/auth/presentation/controller/auth_controller.dart';
import 'features/auth/presentation/controller/auth_state.dart';

/// Root widget. Owns the single [GoRouter] (created once from the app-wide
/// [AuthController]) and exposes the controller to the widget tree so screens
/// can trigger logout / re-auth.
class IamsApp extends StatefulWidget {
  const IamsApp({super.key});

  @override
  State<IamsApp> createState() => _IamsAppState();
}

class _IamsAppState extends State<IamsApp> {
  late final AuthController _auth = sl<AuthController>();
  late final SelectedLocationController _selectedLocation =
      sl<SelectedLocationController>();
  late final GoRouter _router = createRouter(_auth, _selectedLocation);

  @override
  Widget build(BuildContext context) {
    // Brand palette: metallic/steel gray + forest green (from the "T" logo).
    // Green is the primary brand color; metallic gray is the secondary/accent.
    // `ColorScheme.fromSeed` derives a full tonal palette from the green seed,
    // then we override secondary/secondaryContainer so accents read as the
    // brand's metallic gray rather than Material's default seed-derived tone.
    const brandGreen = Color(0xFF2E7D46);
    const brandGray = Color(0xFF7C8AA0);

    final lightScheme = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: Brightness.light,
    ).copyWith(
      secondary: brandGray,
      // brandGray is a mid-light tone (~4.8:1 with this dark slate vs. only
      // ~3.5:1 with white) so on-secondary content stays readable.
      onSecondary: const Color(0xFF21262D),
      secondaryContainer: const Color(0xFFDDE2E9),
      onSecondaryContainer: const Color(0xFF2A303B),
    );

    final darkScheme = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: Brightness.dark,
    ).copyWith(
      secondary: const Color(0xFFAEB8C6),
      onSecondary: const Color(0xFF23282F),
      secondaryContainer: const Color(0xFF3F4753),
      onSecondaryContainer: const Color(0xFFDCE1E8),
    );

    return BlocProvider<AuthController>.value(
      value: _auth,
      // Only the router listens to auth for redirects; screens read the
      // controller directly. Guard rebuilds to nothing visible here.
      child: BlocListener<AuthController, AuthState>(
        listenWhen: (a, b) => a.status != b.status,
        listener: (_, _) {},
        child: MaterialApp.router(
          title: 'IAMS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
          ),
          routerConfig: _router,
        ),
      ),
    );
  }
}
