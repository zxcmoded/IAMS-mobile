import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/hierarchy_sync_service.dart' show HierarchySyncService, SyncLevels;

enum SyncStage { initial, checking, syncing, complete, error }

/// State for the sync/bootstrap screen. [level] identifies which hierarchy
/// level is currently syncing (for the progress label); [errorCode] and
/// [retryable] drive the error UI.
class HierarchySyncState extends Equatable {
  const HierarchySyncState({
    this.stage = SyncStage.initial,
    this.level,
    this.pagesFetched = 0,
    this.itemsUpserted = 0,
    this.errorCode,
    this.errorMessage,
    this.retryable = false,
  });

  final SyncStage stage;
  final String? level;
  final int pagesFetched;
  final int itemsUpserted;
  final String? errorCode;
  final String? errorMessage;
  final bool retryable;

  bool get isComplete => stage == SyncStage.complete;
  bool get isError => stage == SyncStage.error;
  bool get isBusy => stage == SyncStage.checking || stage == SyncStage.syncing;

  @override
  List<Object?> get props => [
        stage,
        level,
        pagesFetched,
        itemsUpserted,
        errorCode,
        errorMessage,
        retryable,
      ];
}

/// Thin wrapper over [HierarchySyncService] for the sync screen. Checks whether
/// the store is already fully synced (skip straight to `complete`) and
/// otherwise runs a sync pass, projecting per-page progress into state.
class HierarchySyncCubit extends Cubit<HierarchySyncState> {
  HierarchySyncCubit(this._service) : super(const HierarchySyncState());

  final HierarchySyncService _service;

  /// Runs a sync pass on entry — **always**, even when the store already looks
  /// fully synced. This matters for correctness: the reachability-gap
  /// mitigation (the cheap full-Company pull + snapshot diff) lives inside
  /// [HierarchySyncService.run], so skipping `run()` would mean a
  /// newly-reachable company enabled after the initial sync is never detected
  /// on subsequent launches. `run()`'s per-level `skip if complete` logic keeps
  /// this cheap — only the low-cardinality Company pass actually re-runs unless
  /// the diff changed something.
  ///
  /// When the store was already fully synced we run "quietly": the visible
  /// progress spinner is suppressed for the cheap Company pass so a routine
  /// no-change launch just passes through to `complete` near-instantly. If the
  /// diff triggers real child-level work, progress surfaces normally.
  Future<void> checkAndSync() async {
    bool alreadySynced;
    try {
      alreadySynced = await _service.checkIsFullySynced();
    } catch (_) {
      // A local read failure shouldn't be fatal — treat as not-synced so the
      // pass runs visibly and surfaces any real error consistently.
      alreadySynced = false;
    }
    if (alreadySynced) {
      emit(const HierarchySyncState(stage: SyncStage.checking));
    }
    await _sync(quiet: alreadySynced);
  }

  /// Retry after an error — re-runs a sync pass (visibly), resuming from
  /// persisted state.
  Future<void> retry() => _sync(quiet: false);

  Future<void> _sync({required bool quiet}) async {
    if (!quiet) emit(const HierarchySyncState(stage: SyncStage.syncing));
    try {
      await _service.run(onProgress: (p) {
        if (p.isError) return; // the rethrow below drives the error state
        // On a quiet (already-synced) pass, don't flash a spinner for the cheap
        // Company check — only surface progress once real child-level work
        // starts (i.e. the reachability diff forced a re-pull).
        if (quiet && p.level == SyncLevels.company) return;
        emit(HierarchySyncState(
          stage: SyncStage.syncing,
          level: p.level,
          pagesFetched: p.pagesFetched,
          itemsUpserted: p.itemsUpserted,
        ));
      });
      emit(const HierarchySyncState(stage: SyncStage.complete));
    } on ApiException catch (e) {
      emit(HierarchySyncState(
        stage: SyncStage.error,
        errorCode: e.code,
        errorMessage: e.message,
        retryable: _isRetryable(e),
      ));
    } catch (_) {
      // Catch-all for non-[ApiException] failures — e.g. a local database
      // (SQLite) error, or a TypeError/FormatException while mapping an
      // unexpected page. Without this the Future error would go unhandled and
      // the cubit would stay in [SyncStage.syncing] forever (spinner spins, no
      // error shown). Surface a generic message rather than leaking raw
      // exception text; treat as retryable so the user can tap retry.
      emit(const HierarchySyncState(
        stage: SyncStage.error,
        errorCode: ApiErrorCode.unknown,
        errorMessage: 'Something went wrong. Please try again.',
        retryable: true,
      ));
    }
  }

  /// Network/transient/server errors are worth retrying; a client error like a
  /// malformed cursor (400) or forbidden parent (403) is not.
  bool _isRetryable(ApiException e) {
    if (e.isNetwork || e.code == ApiErrorCode.rateLimited) return true;
    final status = e.statusCode;
    if (status == null) return true;
    return status >= 500;
  }
}
