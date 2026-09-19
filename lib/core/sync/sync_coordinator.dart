import 'dart:async';

import '../../features/auth/presentation/controller/auth_controller.dart';
import '../../features/auth/presentation/controller/auth_state.dart';
import '../../features/inventory/data/inventory_sync_service.dart';
import '../../features/masterdata/data/hierarchy_sync_service.dart';
import '../network/connectivity_checker.dart';

/// Kicks off the offline data sync **headlessly**, in the background, so it
/// never stands between authentication and the Main Screen.
///
/// This replaces the old blocking `/sync` route + `HierarchySyncScreen` gate.
/// The rule (see the feature spec): navigation to `/companies` must never be
/// blocked or delayed by sync, in either connectivity state.
///
/// * **Online** → fire-and-forget both the master-data hierarchy sync and the
///   inventory sync. They run concurrently and independently; each swallows its
///   own errors (a background sync never surfaces a UI error — a failed attempt
///   just means the next launch/reconnect catches up incrementally, mirroring
///   the philosophy the old `HierarchySyncCubit` applied *after* a failure).
/// * **Offline** → skip both entirely and silently. No error, no delay, no
///   spinner. The Main Screen renders whatever is already in SQLite (possibly
///   nothing on a fresh install — that is fine).
///
/// Plain Dart (no Flutter import) so it is unit-testable with a fake
/// [ConnectivityChecker] and mocked sync services.
class SyncCoordinator {
  // Private fields with public named params — initializing formals can't
  // express this, so the assignments live in the initializer list.
  // ignore_for_file: prefer_initializing_formals
  SyncCoordinator({
    required AuthController auth,
    required ConnectivityChecker connectivity,
    required HierarchySyncService hierarchySync,
    required InventorySyncService inventorySync,
  })  : _auth = auth,
        _connectivity = connectivity,
        _hierarchySync = hierarchySync,
        _inventorySync = inventorySync;

  final AuthController _auth;
  final ConnectivityChecker _connectivity;
  final HierarchySyncService _hierarchySync;
  final InventorySyncService _inventorySync;

  StreamSubscription<AuthState>? _sub;
  bool _running = false;

  /// Wire the coordinator to the session lifecycle. Call once at startup
  /// (after [AuthController.bootstrap]). Fires an initial sync if the restored
  /// session is already authenticated (the bootstrap emit happens before we can
  /// subscribe, so it must be handled explicitly), then triggers on every
  /// later transition into `authenticated` (e.g. a fresh activation).
  void start() {
    if (_auth.state.status == AuthStatus.authenticated) {
      unawaited(triggerBackgroundSync());
    }
    _sub ??= _auth.stream.listen((state) {
      if (state.status == AuthStatus.authenticated) {
        unawaited(triggerBackgroundSync());
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Runs one connectivity-gated background sync pass. Returns once the pass
  /// (or the decision to skip it) is complete — call sites use `unawaited(...)`
  /// so nothing blocks on it, but it is fully awaitable for tests.
  ///
  /// Re-entrancy guarded: a trigger that arrives while a pass is in flight is a
  /// no-op (the in-flight pass will already pick up the latest state).
  Future<void> triggerBackgroundSync() async {
    if (_running) return;
    final online = await _connectivity.isOnline();
    if (!online) return; // Offline: skip silently — never block or error.
    _running = true;
    try {
      await Future.wait([
        _guard(() => _hierarchySync.run()),
        _guard(() => _inventorySync.run()),
      ]);
    } finally {
      _running = false;
    }
  }

  Future<void> _guard(Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      // A background sync never surfaces errors. A plain connectivity failure,
      // a bad page, or a local DB hiccup all just mean "not caught up yet" —
      // the next successful trigger resumes from persisted cursors.
    }
  }
}
