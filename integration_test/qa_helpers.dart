// QA-only helpers shared by the live-verification integration tests in this
// directory. Not part of the product test suite -- exercises the REAL app
// (main()-equivalent boot) against a real device/emulator, real sqflite, and
// the real backend (reached through a local fault-injecting proxy so partial
// network failures / expired-token responses can be deterministically forced
// without needing OS-level airplane-mode or process-kill tooling on CI).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:iams_mobile/app.dart';
import 'package:iams_mobile/core/config/app_config.dart';
import 'package:iams_mobile/core/di/service_locator.dart';
import 'package:iams_mobile/core/storage/app_database.dart';
import 'package:iams_mobile/features/auth/presentation/controller/auth_controller.dart';

/// Pumps a fixed number of frames without asserting the tree "settles" --
/// `pumpAndSettle` is unsafe here because the sync/activation screens show a
/// `CircularProgressIndicator` (an indefinite animation) while a real network
/// call is in flight, and `pumpAndSettle` treats "still animating" as a
/// failure to converge (it throws / the live device binding can surface that
/// as an uncaught test-framework exception even though the app itself is
/// behaving correctly -- confirmed empirically: the app's own ApiException
/// handling was working fine underneath).
Future<void> pumpForAWhile(WidgetTester tester,
    {int iterations = 10, Duration step = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(step);
  }
}

Future<void> bootApp(WidgetTester tester) async {
  await configureDependencies();
  await sl<AppDatabase>().instance;
  await sl<AuthController>().bootstrap();
  await tester.pumpWidget(const IamsApp());
  await pumpForAWhile(tester);
}

const qaActivationKey = 'qa-test-mobile-key-002';

Future<void> activateIfNeeded(WidgetTester tester) async {
  final keyField = find.byKey(const Key('activation_key_field'));
  if (keyField.evaluate().isEmpty) return; // already authenticated
  await tester.enterText(keyField, qaActivationKey);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await pumpForAWhile(tester, iterations: 15);
}

/// Pumps until [finder] appears or [timeout] elapses (sync can take a few
/// seconds against a real network call).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  throw TestFailure('Timed out waiting for $finder');
}

IntegrationTestWidgetsFlutterBinding ensureBinding() =>
    IntegrationTestWidgetsFlutterBinding.ensureInitialized()
        as IntegrationTestWidgetsFlutterBinding;

/// Logs a marker request through the QA fault-injecting proxy (a 404 is
/// expected/ignored -- it never reaches anything meaningful) purely so the
/// host-side proxy request log has an unambiguous boundary between phases
/// when reasoning about it after the whole test run finishes.
Future<void> logPhaseMarker(String label) async {
  try {
    await Dio(BaseOptions(
      baseUrl: '${AppConfig.apiBaseUrl}/api',
      connectTimeout: const Duration(seconds: 5),
    )).get<void>('/qa-marker/$label');
  } catch (_) {
    // Expected to fail -- only exists to appear in the proxy log.
  }
}

/// Simulates a relaunch: tears down the DI graph (GetIt) and the widget tree
/// and rebuilds both from scratch, exactly like a fresh process would --
/// WITHOUT touching the on-device sqflite file or secure-storage entries
/// (those are real OS-level persistence the harness never clears), so
/// whatever the sync engine persisted survives across this boundary just
/// like it would survive an actual app-process kill + relaunch.
Future<void> relaunch(WidgetTester tester) async {
  await sl.reset();
  await bootApp(tester);
}
