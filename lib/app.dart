import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
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
  late final GoRouter _router = createRouter(_auth);

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF1B5E9B);
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
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          routerConfig: _router,
        ),
      ),
    );
  }
}
