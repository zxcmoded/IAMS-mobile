import '../../../core/network/api_exception.dart';
import 'hierarchy_api.dart';
import 'hierarchy_local_data_source.dart';
import 'models/sync_metadata.dart';

/// The hierarchy level names, in the fixed sync order (parents before children
/// so foreign keys resolve). Also the `entity` keys in `sync_metadata` and the
/// SQLite table names (both singular).
class SyncLevels {
  const SyncLevels._();

  static const company = 'company';
  static const location = 'location';
  static const warehouse = 'warehouse';
  static const rack = 'rack';
  static const bin = 'bin';

  /// All five levels, in dependency order.
  static const all = [company, location, warehouse, rack, bin];

  /// The four child levels pulled incrementally (Company is always full).
  static const children = [location, warehouse, rack, bin];
}

/// Progress emitted per page (and once on failure) so the UI can show which
/// level is syncing. On failure [error]/[errorCode] are set and the service
/// also rethrows so the caller can transition to an error state.
class SyncProgress {
  const SyncProgress({
    required this.level,
    this.pagesFetched = 0,
    this.itemsUpserted = 0,
    this.error,
    this.errorCode,
  });

  final String level;
  final int pagesFetched;
  final int itemsUpserted;
  final Object? error;
  final String? errorCode;

  bool get isError => error != null;
}

/// A page reduced to what the sync loop needs — rows already mapped to SQLite
/// shape, plus the pagination signals. Lets the generic level loop stay free of
/// per-level model types.
class _RawPage {
  const _RawPage(this.rows, this.nextCursor, this.hasMore);

  final List<Map<String, Object?>> rows;
  final String? nextCursor;
  final bool hasMore;
}

/// Drives the offline sync of the whole hierarchy into SQLite. Plain Dart (no
/// Flutter import) so it is trivially unit-testable. Holds both the local store
/// and the API — the only place in the app that pairs the two.
///
/// See the contract doc's "Pagination & incremental sync" and "Known gap"
/// sections for the semantics implemented here.
class HierarchySyncService {
  HierarchySyncService(this._local, this._api, {int pageSize = 200})
      // ignore: prefer_initializing_formals
      : _pageSize = pageSize;

  final HierarchyLocalDataSource _local;
  final HierarchyApi _api;
  final int _pageSize;

  DateTime _now() => DateTime.now().toUtc();

  /// `true` iff every one of the five levels is `complete`.
  Future<bool> checkIsFullySynced() async {
    for (final level in SyncLevels.all) {
      final meta = await _local.readSyncMetadata(level);
      if (meta?.syncStatus != SyncStatus.complete) return false;
    }
    return true;
  }

  /// Runs one full sync pass. Idempotent and resumable: the cheap full Company
  /// pass runs every time, already-`complete` child levels are skipped (unless
  /// a reachable-set change forced them back to `pending`), and a level left
  /// `inProgress` by a prior failure resumes from its persisted cursor.
  ///
  /// Reports progress via [onProgress]; on the first API failure it persists
  /// the partial state, reports an error via [onProgress], and rethrows.
  Future<void> run({void Function(SyncProgress)? onProgress}) async {
    // 1. Company — always a full pass (cursor=null), collecting the id set.
    final currentCompanyIds = await _runCompanyPass(onProgress);

    // 2. Reachability diff — force a full re-pull of children on any change.
    final previous = await _local.readReachableSnapshot();
    final forcedReset = <String>{};
    if (!_setEquals(currentCompanyIds, previous)) {
      for (final level in SyncLevels.children) {
        final existing = await _local.readSyncMetadata(level);
        await _local.writeSyncMetadata(SyncMetadata(
          entity: level,
          lastCursor: null,
          syncStatus: SyncStatus.pending,
          lastSyncedAtUtc: existing?.lastSyncedAtUtc,
          syncVersion: existing?.syncVersion ?? 0,
        ));
        forcedReset.add(level);
      }
    }
    await _local.replaceReachableSnapshot(currentCompanyIds);

    // 3. Company is now durably caught up for this pass.
    await _markComplete(SyncLevels.company);

    // 4. Child levels in dependency order.
    for (final level in SyncLevels.children) {
      final meta = await _local.readSyncMetadata(level);
      final alreadyDone = meta?.syncStatus == SyncStatus.complete &&
          !forcedReset.contains(level);
      if (alreadyDone) continue;

      // Persist inProgress *before* the first network call so a crash mid-page
      // resumes rather than looking untouched.
      final startCursor = meta?.lastCursor;
      await _local.writeSyncMetadata(SyncMetadata(
        entity: level,
        lastCursor: startCursor,
        syncStatus: SyncStatus.inProgress,
        lastSyncedAtUtc: meta?.lastSyncedAtUtc,
        syncVersion: meta?.syncVersion ?? 0,
      ));

      try {
        await _syncChildLevel(level, startCursor, onProgress);
        await _markComplete(level);
      } on ApiException catch (e) {
        // Leave status at inProgress with whatever cursor last committed; do
        // not touch downstream levels.
        onProgress?.call(SyncProgress(
          level: level,
          error: e,
          errorCode: e.code,
        ));
        rethrow;
      }
    }
  }

  Future<Set<String>> _runCompanyPass(
      void Function(SyncProgress)? onProgress) async {
    final ids = <String>{};
    var pages = 0;
    var items = 0;
    String? cursor;
    while (true) {
      final page = await _api.getCompanies(cursor: cursor, pageSize: _pageSize);
      await _local.upsertPage(
        SyncLevels.company,
        page.items.map((c) => c.toRow()).toList(growable: false),
      );
      ids.addAll(page.items.map((c) => c.id));
      pages++;
      items += page.items.length;
      onProgress?.call(SyncProgress(
        level: SyncLevels.company,
        pagesFetched: pages,
        itemsUpserted: items,
      ));
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
    return ids;
  }

  Future<void> _syncChildLevel(
    String level,
    String? startCursor,
    void Function(SyncProgress)? onProgress,
  ) async {
    var pages = 0;
    var items = 0;
    String? cursor = startCursor;
    while (true) {
      final page = await _fetchChildPage(level, cursor);
      // Upsert rows and advance the stored cursor atomically. The cursor is
      // advanced only from a non-null nextCursor (empty-page rule).
      await _local.upsertPageAndAdvanceCursor(
        table: level,
        entity: level,
        rows: page.rows,
        nextCursor: page.nextCursor,
      );
      pages++;
      items += page.rows.length;
      onProgress?.call(SyncProgress(
        level: level,
        pagesFetched: pages,
        itemsUpserted: items,
      ));
      if (!page.hasMore || page.nextCursor == null) break;
      cursor = page.nextCursor;
    }
  }

  Future<_RawPage> _fetchChildPage(String level, String? cursor) async {
    switch (level) {
      case SyncLevels.location:
        final p = await _api.getLocations(cursor: cursor, pageSize: _pageSize);
        return _RawPage(
          p.items.map((e) => e.toRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      case SyncLevels.warehouse:
        final p = await _api.getWarehouses(cursor: cursor, pageSize: _pageSize);
        return _RawPage(
          p.items.map((e) => e.toRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      case SyncLevels.rack:
        final p = await _api.getRacks(cursor: cursor, pageSize: _pageSize);
        return _RawPage(
          p.items.map((e) => e.toRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      case SyncLevels.bin:
        final p = await _api.getBins(cursor: cursor, pageSize: _pageSize);
        return _RawPage(
          p.items.map((e) => e.toRow()).toList(growable: false),
          p.nextCursor,
          p.hasMore,
        );
      default:
        throw ArgumentError('Not a child level: $level');
    }
  }

  Future<void> _markComplete(String level) async {
    final meta = await _local.readSyncMetadata(level);
    await _local.writeSyncMetadata(SyncMetadata(
      entity: level,
      lastCursor: meta?.lastCursor,
      syncStatus: SyncStatus.complete,
      lastSyncedAtUtc: _now(),
      syncVersion: (meta?.syncVersion ?? 0) + 1,
    ));
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
