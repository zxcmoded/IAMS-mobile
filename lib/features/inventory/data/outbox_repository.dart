import '../../../core/network/api_exception.dart';
import '../../../core/storage/device_id_provider.dart';
import '../../../core/util/uuid.dart';
import 'inventory_api.dart';
import 'models/cached_stock_level.dart';
import 'models/inventory_enums.dart';
import 'models/inventory_item_detail.dart';
import 'models/outbox_entry.dart';
import 'models/stock_conflict.dart';
import 'models/stock_count_response.dart';
import 'models/stock_movement_response.dart';
import 'outbox_local_data_source.dart';

/// The result the repository hands back after attempting a mutation, so a
/// screen can render the right inline state without re-deriving it.
class MutationResult {
  const MutationResult({
    required this.outcome,
    required this.entry,
    this.movement,
    this.count,
    this.conflicts = const [],
    this.errorCode,
    this.errorMessage,
  });

  final MutationOutcome outcome;
  final OutboxEntry entry;
  final StockMovementResponse? movement;
  final StockCountResponse? count;
  final List<StockConflict> conflicts;
  final String? errorCode;
  final String? errorMessage;

  bool get isServerAccepted =>
      outcome == MutationOutcome.applied || outcome == MutationOutcome.replayed;
  bool get isQueued => outcome == MutationOutcome.queued;
  bool get isConflict => outcome == MutationOutcome.conflict;
}

/// Summary of a reconnect replay pass.
class PushSummary {
  const PushSummary({
    required this.attempted,
    required this.accepted,
    required this.conflicted,
    required this.failed,
    required this.stoppedOffline,
  });

  final int attempted;
  final int accepted;
  final int conflicted;
  final int failed;

  /// True if the pass halted because the network went away mid-queue — the
  /// remaining rows stay pending for the next attempt.
  final bool stoppedOffline;
}

/// Offline-first orchestration for every F4 mutation. The one place that pairs
/// the local outbox/cache with the API — mirrors how `HierarchySyncService`
/// pairs the local store with the sync API.
///
/// Flow per mutation:
/// 1. Mint a stable `idempotencyKey`, stamp `base*StockVersion` from the
///    last-observed cache versions, and write a `pending` outbox row.
/// 2. Attempt to push immediately. The **first** attempt omits the base
///    versions (a fresh online action is last-writer-wins); any later replay
///    includes them so a real concurrent change surfaces as
///    `409 stock_version_conflict`.
/// 3. On success reconcile the cache from the authoritative response (the
///    bumped `version` especially) and mark the row `synced`. On network
///    failure leave it `pending` (queued). On `409` mark it `conflict` and
///    rebase the cache from the returned current state. On `422`/`400`/`404`
///    mark it `failed`.
///
/// Reads never mutate the cache optimistically; instead the item-detail layer
/// overlays each pending row's per-bin delta on top of the observed on-hand, so
/// discarding a queued row cleanly removes its effect with no revert bookkeeping.
class OutboxRepository {
  OutboxRepository(this._local, this._api, this._deviceIds);

  final OutboxLocalDataSource _local;
  final InventoryApi _api;
  final DeviceIdProvider _deviceIds;

  static const _baseVersionKeys = {
    'baseStockVersion',
    'baseSourceStockVersion',
    'baseDestinationStockVersion',
  };

  DateTime _now() => DateTime.now().toUtc();

  // ---- Read passthroughs (for the detail cubit) ----------------------------

  Future<List<OutboxEntry>> outboxForItem(String itemId) =>
      _local.getOutboxForItem(itemId);

  Future<List<CachedStockLevel>> cachedLevelsForItem(String itemId) =>
      _local.getStockLevelsForItem(itemId);

  /// Reconcile the cache from a fresh authoritative item-detail fetch, so the
  /// next offline mutation stamps up-to-date base versions.
  Future<void> reconcileFromDetail(InventoryItemDetail detail) async {
    final now = _now();
    final levels = detail.stockByBin
        .map((b) => CachedStockLevel(
              inventoryItemId: detail.id,
              binId: b.binId,
              quantityOnHand: b.quantityOnHand,
              version: b.version,
              updatedAtUtc: now,
            ))
        .toList(growable: false);
    await _local.upsertStockLevels(levels);
  }

  // ---- Mutations ------------------------------------------------------------

  Future<MutationResult> receive({
    required String inventoryItemId,
    required String destinationBinId,
    required double quantity,
  }) async {
    final base = await _baseVersion(inventoryItemId, destinationBinId);
    return _commit(
      kind: MutationKind.receive,
      inventoryItemId: inventoryItemId,
      core: {
        'inventoryItemId': inventoryItemId,
        'destinationBinId': destinationBinId,
        'quantity': quantity,
      },
      baseVersions: {
        'baseDestinationStockVersion': ?base,
      },
    );
  }

  Future<MutationResult> transfer({
    required String inventoryItemId,
    required String sourceBinId,
    required String destinationBinId,
    required double quantity,
  }) async {
    final baseSource = await _baseVersion(inventoryItemId, sourceBinId);
    final baseDest = await _baseVersion(inventoryItemId, destinationBinId);
    return _commit(
      kind: MutationKind.transfer,
      inventoryItemId: inventoryItemId,
      core: {
        'inventoryItemId': inventoryItemId,
        'sourceBinId': sourceBinId,
        'destinationBinId': destinationBinId,
        'quantity': quantity,
      },
      baseVersions: {
        'baseSourceStockVersion': ?baseSource,
        'baseDestinationStockVersion': ?baseDest,
      },
    );
  }

  Future<MutationResult> adjust({
    required String inventoryItemId,
    required String binId,
    required double quantityDelta,
    required String reason,
  }) async {
    final base = await _baseVersion(inventoryItemId, binId);
    return _commit(
      kind: MutationKind.adjust,
      inventoryItemId: inventoryItemId,
      core: {
        'inventoryItemId': inventoryItemId,
        'binId': binId,
        'quantityDelta': quantityDelta,
        'reason': reason,
      },
      baseVersions: {
        'baseStockVersion': ?base,
      },
    );
  }

  Future<MutationResult> count({
    required String inventoryItemId,
    required String binId,
    required double countedQuantity,
  }) async {
    final base = await _baseVersion(inventoryItemId, binId);
    return _commit(
      kind: MutationKind.count,
      inventoryItemId: inventoryItemId,
      core: {
        'inventoryItemId': inventoryItemId,
        'binId': binId,
        'countedQuantity': countedQuantity,
      },
      baseVersions: {
        'baseStockVersion': ?base,
      },
    );
  }

  Future<MutationResult> _commit({
    required MutationKind kind,
    required String inventoryItemId,
    required Map<String, dynamic> core,
    required Map<String, int> baseVersions,
  }) async {
    final key = newUuidV4();
    final now = _now();
    final deviceId = await _safeDeviceId();
    final payload = <String, dynamic>{
      'idempotencyKey': key,
      ...core,
      ...baseVersions,
      'deviceId': ?deviceId,
      'clientCreatedAtUtc': now.toIso8601String(),
    };
    final entry = OutboxEntry(
      idempotencyKey: key,
      kind: kind,
      inventoryItemId: inventoryItemId,
      payload: payload,
      status: OutboxStatus.pending,
      createdAtUtc: now,
    );
    await _local.insertOutbox(entry);
    return _push(entry);
  }

  // ---- Replay / conflict resolution ----------------------------------------

  /// Replay every `pending` mutation in submission order. Stops on the first
  /// network failure (still offline) so ordering is preserved; business errors
  /// (409/422/400/404) mark that row and the pass continues.
  Future<PushSummary> pushPending() async {
    final pending = await _local.getPendingOrdered();
    var accepted = 0, conflicted = 0, failed = 0, attempted = 0;
    for (final entry in pending) {
      attempted++;
      final result = await _push(entry);
      switch (result.outcome) {
        case MutationOutcome.applied:
        case MutationOutcome.replayed:
          accepted++;
        case MutationOutcome.conflict:
          conflicted++;
        case MutationOutcome.insufficientStock:
        case MutationOutcome.rejected:
          failed++;
        case MutationOutcome.queued:
          // Network went away again — stop, leave the rest pending.
          return PushSummary(
            attempted: attempted,
            accepted: accepted,
            conflicted: conflicted,
            failed: failed,
            stoppedOffline: true,
          );
      }
    }
    return PushSummary(
      attempted: attempted,
      accepted: accepted,
      conflicted: conflicted,
      failed: failed,
      stoppedOffline: false,
    );
  }

  /// Re-attempt a `conflict`/`failed` row after the user chooses to proceed.
  /// Re-stamps the base versions from the (now rebased) cache so the retry is
  /// applied on top of the latest server state, then pushes. This is the
  /// minimal "review" affordance for Phase 2a — a full conflict-resolution
  /// screen lands with the F11 Sync tab.
  Future<MutationResult> retryEntry(String idempotencyKey) async {
    final entry = await _local.getOutbox(idempotencyKey);
    if (entry == null) {
      throw StateError('No outbox entry for $idempotencyKey');
    }
    final rebased = await _restampBaseVersions(entry);
    final pending = rebased.copyWith(
      status: OutboxStatus.pending,
      updatedAtUtc: _now(),
      lastErrorCode: null,
      lastErrorMessage: null,
    );
    await _local.updateOutbox(pending);
    return _push(pending);
  }

  /// Drop a queued/conflicted/failed mutation. Because on-hand is never mutated
  /// optimistically (the detail view overlays pending deltas at read time),
  /// removing the row is all that's needed — its effect simply stops being
  /// overlaid.
  Future<void> discardEntry(String idempotencyKey) =>
      _local.deleteOutbox(idempotencyKey);

  // ---- Core push ------------------------------------------------------------

  Future<MutationResult> _push(OutboxEntry entry) async {
    // Increment the attempt count up front so the *next* replay is treated as a
    // replay (includes base versions) even if this attempt throws.
    final attempting = entry.copyWith(
      attemptCount: entry.attemptCount + 1,
      updatedAtUtc: _now(),
    );

    final body = Map<String, dynamic>.of(entry.payload);
    if (!entry.isReplay) {
      // First online attempt: skip the concurrency check entirely.
      body.removeWhere((k, _) => _baseVersionKeys.contains(k));
    }

    try {
      if (entry.kind == MutationKind.count) {
        final resp = await _callCount(body);
        await _reconcileCount(entry.inventoryItemId, body, resp);
        final synced = attempting.copyWith(
          status: OutboxStatus.synced,
          response: _countJson(resp),
          lastErrorCode: null,
          lastErrorMessage: null,
        );
        await _local.updateOutbox(synced);
        return MutationResult(
          outcome:
              resp.replayed ? MutationOutcome.replayed : MutationOutcome.applied,
          entry: synced,
          count: resp,
        );
      }

      final resp = await _callMovement(entry.kind, body);
      await _reconcileMovement(entry.inventoryItemId, resp);
      final synced = attempting.copyWith(
        status: OutboxStatus.synced,
        response: _movementJson(resp),
        lastErrorCode: null,
        lastErrorMessage: null,
      );
      await _local.updateOutbox(synced);
      return MutationResult(
        outcome:
            resp.replayed ? MutationOutcome.replayed : MutationOutcome.applied,
        entry: synced,
        movement: resp,
      );
    } on ApiException catch (e) {
      return _handleFailure(attempting, e);
    } catch (_) {
      // Non-[ApiException] (local db/parse). Treat as retryable: keep pending.
      final queued = attempting.copyWith(
        status: OutboxStatus.pending,
        lastErrorCode: ApiErrorCode.unknown,
        lastErrorMessage: 'Something went wrong. Will retry.',
      );
      await _local.updateOutbox(queued);
      return MutationResult(
        outcome: MutationOutcome.queued,
        entry: queued,
        errorCode: ApiErrorCode.unknown,
        errorMessage: queued.lastErrorMessage,
      );
    }
  }

  Future<MutationResult> _handleFailure(
    OutboxEntry attempting,
    ApiException e,
  ) async {
    if (e.isNetwork) {
      final queued = attempting.copyWith(
        status: OutboxStatus.pending,
        lastErrorCode: e.code,
        lastErrorMessage: e.message,
      );
      await _local.updateOutbox(queued);
      return MutationResult(
        outcome: MutationOutcome.queued,
        entry: queued,
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    if (e.isStockVersionConflict) {
      final conflicts = StockConflict.listFrom(e.extensions['conflicts']);
      await _rebaseFromConflicts(attempting.inventoryItemId, conflicts);
      final conflicted = attempting.copyWith(
        status: OutboxStatus.conflict,
        lastErrorCode: e.code,
        lastErrorMessage: e.message,
      );
      await _local.updateOutbox(conflicted);
      return MutationResult(
        outcome: MutationOutcome.conflict,
        entry: conflicted,
        conflicts: conflicts,
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    // 422 insufficient_stock, 400 validation_failed, 404 not_found, etc.
    final failed = attempting.copyWith(
      status: OutboxStatus.failed,
      lastErrorCode: e.code,
      lastErrorMessage: e.message,
    );
    await _local.updateOutbox(failed);
    return MutationResult(
      outcome: e.isInsufficientStock
          ? MutationOutcome.insufficientStock
          : MutationOutcome.rejected,
      entry: failed,
      errorCode: e.code,
      errorMessage: e.message,
    );
  }

  Future<StockMovementResponse> _callMovement(
    MutationKind kind,
    Map<String, dynamic> body,
  ) {
    final clientCreatedAtUtc = _parseTime(body['clientCreatedAtUtc']);
    final deviceId = body['deviceId'] as String?;
    final key = body['idempotencyKey'] as String;
    final itemId = body['inventoryItemId'] as String;
    switch (kind) {
      case MutationKind.receive:
        return _api.receive(
          idempotencyKey: key,
          inventoryItemId: itemId,
          destinationBinId: body['destinationBinId'] as String,
          quantity: _num(body['quantity']),
          baseDestinationStockVersion:
              body['baseDestinationStockVersion'] as int?,
          deviceId: deviceId,
          clientCreatedAtUtc: clientCreatedAtUtc,
        );
      case MutationKind.transfer:
        return _api.transfer(
          idempotencyKey: key,
          inventoryItemId: itemId,
          sourceBinId: body['sourceBinId'] as String,
          destinationBinId: body['destinationBinId'] as String,
          quantity: _num(body['quantity']),
          baseSourceStockVersion: body['baseSourceStockVersion'] as int?,
          baseDestinationStockVersion:
              body['baseDestinationStockVersion'] as int?,
          deviceId: deviceId,
          clientCreatedAtUtc: clientCreatedAtUtc,
        );
      case MutationKind.adjust:
        return _api.adjust(
          idempotencyKey: key,
          inventoryItemId: itemId,
          binId: body['binId'] as String,
          quantityDelta: _num(body['quantityDelta']),
          reason: body['reason'] as String,
          baseStockVersion: body['baseStockVersion'] as int?,
          deviceId: deviceId,
          clientCreatedAtUtc: clientCreatedAtUtc,
        );
      case MutationKind.count:
        throw ArgumentError('count is not a movement');
    }
  }

  Future<StockCountResponse> _callCount(Map<String, dynamic> body) => _api.count(
        idempotencyKey: body['idempotencyKey'] as String,
        inventoryItemId: body['inventoryItemId'] as String,
        binId: body['binId'] as String,
        countedQuantity: _num(body['countedQuantity']),
        baseStockVersion: body['baseStockVersion'] as int?,
        deviceId: body['deviceId'] as String?,
        clientCreatedAtUtc: _parseTime(body['clientCreatedAtUtc']),
      );

  // ---- Cache reconcile ------------------------------------------------------

  Future<void> _reconcileMovement(
    String itemId,
    StockMovementResponse resp,
  ) async {
    final now = _now();
    final levels = resp.stockLevels
        .map((s) => CachedStockLevel(
              inventoryItemId: itemId,
              binId: s.binId,
              quantityOnHand: s.quantityOnHand,
              version: s.version,
              updatedAtUtc: now,
            ))
        .toList(growable: false);
    await _local.upsertStockLevels(levels);
  }

  Future<void> _reconcileCount(
    String itemId,
    Map<String, dynamic> body,
    StockCountResponse resp,
  ) async {
    final binId = body['binId'] as String;
    // Over-threshold counts park pending with NO stock change → on-hand stays
    // at the system snapshot; within-threshold/approved counts set it to the
    // counted quantity. Either way the version echoed back is authoritative.
    final qty = resp.status.isPendingApproval
        ? resp.systemQuantity
        : resp.countedQuantity;
    await _local.upsertStockLevel(CachedStockLevel(
      inventoryItemId: itemId,
      binId: binId,
      quantityOnHand: qty,
      version: resp.stockVersion,
      updatedAtUtc: _now(),
    ));
  }

  Future<void> _rebaseFromConflicts(
    String itemId,
    List<StockConflict> conflicts,
  ) async {
    if (conflicts.isEmpty) return;
    final now = _now();
    final levels = conflicts
        .map((c) => CachedStockLevel(
              inventoryItemId: itemId,
              binId: c.binId,
              quantityOnHand: c.currentQuantityOnHand,
              version: c.currentVersion,
              updatedAtUtc: now,
            ))
        .toList(growable: false);
    await _local.upsertStockLevels(levels);
  }

  /// Re-read the current cache versions and rewrite the entry's stored base
  /// versions, so a retry after a conflict stamps the latest observed version.
  Future<OutboxEntry> _restampBaseVersions(OutboxEntry entry) async {
    final payload = Map<String, dynamic>.of(entry.payload);
    final itemId = entry.inventoryItemId;

    Future<void> restamp(String binKey, String versionKey) async {
      final binId = payload[binKey] as String?;
      if (binId == null) return;
      final base = await _baseVersion(itemId, binId);
      if (base != null) {
        payload[versionKey] = base;
      } else {
        payload.remove(versionKey);
      }
    }

    switch (entry.kind) {
      case MutationKind.receive:
        await restamp('destinationBinId', 'baseDestinationStockVersion');
      case MutationKind.transfer:
        await restamp('sourceBinId', 'baseSourceStockVersion');
        await restamp('destinationBinId', 'baseDestinationStockVersion');
      case MutationKind.adjust:
      case MutationKind.count:
        await restamp('binId', 'baseStockVersion');
    }
    return entry.copyWith(payload: payload);
  }

  Future<int?> _baseVersion(String itemId, String binId) async {
    final cached = await _local.getStockLevel(itemId, binId);
    return cached?.version;
  }

  Future<String?> _safeDeviceId() async {
    try {
      final id = await _deviceIds.getDeviceId();
      return id.isEmpty ? null : id;
    } catch (_) {
      // Device id is best-effort audit metadata; never block a mutation on it.
      return null;
    }
  }

  double _num(Object? v) => (v as num).toDouble();

  DateTime? _parseTime(Object? v) =>
      v is String ? DateTime.parse(v).toUtc() : null;

  Map<String, dynamic> _movementJson(StockMovementResponse r) => {
        'transactionId': r.transactionId,
        'status': r.status.name,
        'replayed': r.replayed,
      };

  Map<String, dynamic> _countJson(StockCountResponse r) => {
        'id': r.id,
        'status': r.status.name,
        'variance': r.variance,
        'replayed': r.replayed,
      };
}
