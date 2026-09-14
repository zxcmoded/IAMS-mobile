import 'package:flutter/material.dart';

import 'app.dart';
import 'core/di/service_locator.dart';
import 'features/auth/presentation/controller/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // Restore any persisted session before the first frame so the router lands
  // on the correct screen immediately.
  await sl<AuthController>().bootstrap();
  runApp(const IamsApp());
}
