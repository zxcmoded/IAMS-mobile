import '../../../core/network/api_exception.dart';
import '../../masterdata/data/hierarchy_api.dart';
import '../../masterdata/data/models/sync_metadata.dart';
import 'inventory_local_data_source.dart';
import 'inventory_sync_api.dart';

/// The inventory sync entity names, in fixed dependency order (items before
/// stock levels, so a stock row's item exists locally first — mirroring the
/// hierarchy's parents-before-children convention). Also the `entity` keys in
/// `sync_metadata`.
class InventorySyncEntities {
  const InventorySyncEntities._();

  static const item = 'inventory_item';
  static const stockLevel = 'stock_level';

  /// Both feeds, in dependency order.
  static const all = [item, stockLevel];
}

/// Progress emitted per page (and once on failure) so a caller could show which
/// feed is syncing. On failure [error]/[errorCode] are set and the service also
/// rethrows so the caller can react.
class InventorySyncProgress {
  const InventorySyncProgress({
    required this.entity,
    this.pagesFetched = 0,
    this.itemsUpserted = 0,
    this.error,
    this.errorCode,
  });

  final String entity;
  final int pagesFetched;
  final int itemsUpserted;
  final Object? error;
  final String? errorCode;

  bool get isError => error != null;
}

/// Drives the offline sync of the two inventory feeds (`inventory_item` then
/// `stock_level`) into SQLite. Plain Dart (no Flutter import) so it is trivially
/// unit-testable. Structurally a twin of `HierarchySyncService`: incremental,
/// resumable, and idempotent, with the same reachability-diff mitigation.
///
/// **Reachability gap (same shape as the hierarchy feeds'):** a company newly
/// visible to the caller (e.g. a SuperAdmin after a company is created
/// system-wide) does not retroactively advance that company's inventory rows'
/// `SyncCursorUtc`, so an incremental poll alone would never surface that
/// company's inventory. So every pass does a cheap full Company pull, diffs the
/// reachable-company set against its own persisted snapshot, and — on any
/// change — forces a full re-pull (`cursor = null`) of *both* inventory feeds.
/// This snapshot is inventory's own (`inventory_reachable_snapshot`), kept
/// separate from the hierarchy sync's so the two can run concurrently without
/// racing on a shared diff basis. Company is low-cardinality, so the extra pull
/// is cheap — the same trade-off the hierarchy sync already accepts for a full
/// Company pass every launch.
class InventorySyncService {
  InventorySyncService(
    this._local,
    this._syncApi,
    this._companiesApi, {
    int pageSize = 200,
  })
      // ignore: prefer_initializing_formals
      : _pageSize = pageSize;

  final InventoryLocalDataSource _local;
  final InventorySyncApi _syncApi;
  final HierarchyApi _companiesApi;
  final int _pageSize;

  DateTime _now() => DateTime.now().toUtc();

  /// `true` iff both feeds are `complete`.
  Future<bool> checkIsFullySynced() async {
    for (final entity in InventorySyncEntities.all) {
      final meta = await _local.readSyncMetadata(entity);
      if (meta?.syncStatus != SyncStatus.complete) return false;
    }
    return true;
  }

  /// Runs one full sync pass. Idempotent and resumable: the cheap full Company
  /// reachability pass runs every time, already-`complete` feeds are skipped
  /// (unless a reachable-set change forced them back to `pending`), and a feed
  /// left `inProgress` by a prior failure resumes from its persisted cursor.
  ///
  /// On the first API failure it persists the partial state, reports an error
  /// via [onProgress], and rethrows.
  Future<void> run({void Function(InventorySyncProgress)? onProgress}) async {
    // 1. Determine the currently-reachable company set (full Company pull).
    final currentCompanyIds = await _reachableCompanyIds();

    // 2. Reachability diff — force a full re-pull of both feeds on any change.
    final previous = await _local.readReachableSnapshot();
    final forcedReset = <String>{};
    if (!_setEquals(currentCompanyIds, previous)) {
      for (final entity in InventorySyncEntities.all) {
        final existing = await _local.readSyncMetadata(entity);
        await _local.writeSyncMetadata(SyncMetadata(
          entity: entity,
          lastCursor: null,
          syncStatus: SyncStatus.pending,
          lastSyncedAtUtc: existing?.lastSyncedAtUtc,
          syncVersion: existing?.syncVersion ?? 0,
        ));
        forcedReset.add(entity);
      }
    }
    await _local.replaceReachableSnapshot(currentCompanyIds);

    // 3. Feeds in dependency order.
    for (final entity in InventorySyncEntities.all) {
      final meta = await _local.readSyncMetadata(entity);
      final alreadyDone = meta?.syncStatus == SyncStatus.complete &&
          !forcedReset.contains(entity);
      if (alreadyDone) continue;

      // Persist inProgress *before* the first network call so a crash mid-page
      // resumes rather than looking untouched.
      final startCursor = meta?.lastCursor;
      await _local.writeSyncMetadata(SyncMetadata(
        entity: entity,
        lastCursor: startCursor,
        syncStatus: SyncStatus.inProgress,
        lastSyncedAtUtc: meta?.lastSyncedAtUtc,
        syncVersion: meta?.syncVersion ?? 0,
      ));

      try {
        await _syncEntity(entity, startCursor, onProgress);
        await _markComplete(entity);
      } on ApiException catch (e) {
        onProgress?.call(InventorySyncProgress(
          entity: entity,
          error: e,
          errorCode: e.code,
        ));
        rethrow;
      }
    }
  }

  /// Full Company pull (cursor = null), collecting the reachable id set. Does
  /// **not** persist companies — that table is owned by the hierarchy sync;
  /// inventory only needs the id set for its reachability diff.
  Future<Set<String>> _reachableCompanyIds() async {
    final ids = <String>{};
    String? cursor;
    while (true) {
      final page =
          await _companiesApi.getCompanies(cursor: cursor, pageSize: _pageSize);
      ids.addAll(page.items.map((c) => c.id));
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    return ids;
  }

  Future<void> _syncEntity(
    String entity,
    String? startCursor,
    void Function(InventorySyncProgress)? onProgress,
  ) async {
    final table = _tableFor(entity);
    var pages = 0;
    var items = 0;
    String? cursor = startCursor;
    while (true) {
      final (rows, nextCursor, hasMore) = await _fetchPage(entity, cursor);
      // Upsert rows and advance the stored cursor atomically. The cursor is
      // advanced only from a non-null nextCursor (empty-page rule).
      await _local.upsertPageAndAdvanceCursor(
        table: table,
        entity: entity,
        rows: rows,
        nextCursor: nextCursor,
      );
      pages++;
      items += rows.length;
      onProgress?.call(InventorySyncProgress(
        entity: entity,
        pagesFetched: pages,
        itemsUpserted: items,
      ));
      if (!hasMore || nextCursor == null) break;
      cursor = nextCursor;
    }
  }

  Future<(List<Map<String, Object?>>, String?, bool)> _fetchPage(
    String entity,
    String? cursor,
  ) async {
    switch (entity) {
      case InventorySyncEntities.item:
        final p = await _syncApi.getItems(cursor: cursor, pageSize: _pageSize);
        return (
          p.items.map((e) => e.toRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      case InventorySyncEntities.stockLevel:
        final p =
            await _syncApi.getStockLevels(cursor: cursor, pageSize: _pageSize);
        return (
          p.items.map((e) => e.toCacheRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      default:
        throw ArgumentError('Unknown inventory sync entity: $entity');
    }
  }

  String _tableFor(String entity) => switch (entity) {
        InventorySyncEntities.item => 'inventory_item',
        InventorySyncEntities.stockLevel => 'stock_version_cache',
        _ => throw ArgumentError('Unknown inventory sync entity: $entity'),
      };

  Future<void> _markComplete(String entity) async {
    final meta = await _local.readSyncMetadata(entity);
    await _local.writeSyncMetadata(SyncMetadata(
      entity: entity,
      lastCursor: meta?.lastCursor,
      syncStatus: SyncStatus.complete,
      lastSyncedAtUtc: _now(),
      syncVersion: (meta?.syncVersion ?? 0) + 1,
    ));
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
