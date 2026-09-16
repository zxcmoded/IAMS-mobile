import 'package:flutter/material.dart';

import 'app.dart';
import 'core/di/service_locator.dart';
import 'core/storage/app_database.dart';
import 'features/auth/presentation/controller/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // Open the local SQLite store up front so any open/migration failure surfaces
  // before the first frame (mirrors the explicit bootstrap await below).
  await sl<AppDatabase>().instance;
  // Restore any persisted session before the first frame so the router lands
  // on the correct screen immediately.
  await sl<AuthController>().bootstrap();
  runApp(const IamsApp());
}
