import 'package:flutter/material.dart';

import 'app.dart';
import 'core/di/service_locator.dart';
import 'core/storage/app_database.dart';
import 'core/sync/sync_coordinator.dart';
import 'features/access/presentation/controller/selected_location_controller.dart';
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
  // Restore the persisted current-location selection before the first frame too
  // — the router's one-time location gate reads it synchronously, so it must be
  // loaded before the initial redirect runs.
  await sl<SelectedLocationController>().load();
  // Wire the headless background sync (connectivity-gated, fire-and-forget). It
  // never blocks the first frame or navigation to the Main Screen — if the
  // restored session is already authenticated it kicks off a background pass;
  // otherwise it waits for a later activation. Deliberately NOT awaited.
  sl<SyncCoordinator>().start();
  runApp(const IamsApp());
}
