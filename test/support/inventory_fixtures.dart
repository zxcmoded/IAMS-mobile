import 'package:iams_mobile/features/inventory/data/inventory_local_data_source.dart';
import 'package:iams_mobile/core/storage/device_id_provider.dart';
import 'package:iams_mobile/features/inventory/data/models/cached_stock_level.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item_detail.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_item_sync.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/models/stock_level_sync.dart';
import 'package:iams_mobile/features/inventory/data/outbox_local_data_source.dart';
import 'package:iams_mobile/features/masterdata/data/models/sync_metadata.dart';

/// A fixed device id so mutation payloads are deterministic in tests.
class FakeDeviceIdProvider implements DeviceIdProvider {
  FakeDeviceIdProvider([this.id = 'device-test']);
  final String id;
  @override
  Future<String> getDeviceId() async => id;
}

/// In-memory [OutboxLocalDataSource] mirroring the SQLite behaviour the outbox
/// relies on: idempotency-key-keyed upsert (replace), insertion-order
/// enumeration (the `created_at, rowid` proxy), and (item, bin)-keyed stock
/// cache. No platform channel / real DB needed — same approach as
/// `FakeHierarchyLocalDataSource`.
class FakeOutboxLocalDataSource implements OutboxLocalDataSource {
  final Map<String, OutboxEntry> _outbox = {}; // preserves insertion order
  final Map<String, CachedStockLevel> _cache = {};

  static String _cacheKey(String itemId, String binId) => '$itemId|$binId';

  // ---- Test helpers ---------------------------------------------------------

  List<OutboxEntry> get allOutbox => _outbox.values.toList(growable: false);

  void seedStock(CachedStockLevel level) =>
      _cache[_cacheKey(level.inventoryItemId, level.binId)] = level;

  // ---- Outbox ---------------------------------------------------------------

  @override
  Future<void> insertOutbox(OutboxEntry entry) async {
    _outbox[entry.idempotencyKey] = entry;
  }

  @override
  Future<void> updateOutbox(OutboxEntry entry) async {
    _outbox[entry.idempotencyKey] = entry;
  }

  @override
  Future<void> deleteOutbox(String idempotencyKey) async {
    _outbox.remove(idempotencyKey);
  }

  @override
  Future<OutboxEntry?> getOutbox(String idempotencyKey) async =>
      _outbox[idempotencyKey];

  @override
  Future<List<OutboxEntry>> getOutboxForItem(String inventoryItemId) async =>
      _outbox.values
          .where((e) => e.inventoryItemId == inventoryItemId)
          .toList(growable: false);

  @override
  Future<List<OutboxEntry>> getPendingOrdered() async => _outbox.values
      .where((e) => e.status == OutboxStatus.pending)
      .toList(growable: false);

  @override
  Future<List<OutboxEntry>> getOverlayEntries() async => _outbox.values
      .where((e) =>
          e.status == OutboxStatus.pending || e.status == OutboxStatus.conflict)
      .toList(growable: false);

  @override
  Future<int> countByStatus(List<OutboxStatus> statuses) async =>
      _outbox.values.where((e) => statuses.contains(e.status)).length;

  // ---- Stock cache ----------------------------------------------------------

  @override
  Future<CachedStockLevel?> getStockLevel(
          String inventoryItemId, String binId) async =>
      _cache[_cacheKey(inventoryItemId, binId)];

  @override
  Future<List<CachedStockLevel>> getStockLevelsForItem(
          String inventoryItemId) async =>
      _cache.values
          .where((c) => c.inventoryItemId == inventoryItemId)
          .toList(growable: false);

  @override
  Future<void> upsertStockLevel(CachedStockLevel level) async {
    _cache[_cacheKey(level.inventoryItemId, level.binId)] = level;
  }

  @override
  Future<void> upsertStockLevels(List<CachedStockLevel> levels) async {
    for (final level in levels) {
      _cache[_cacheKey(level.inventoryItemId, level.binId)] = level;
    }
  }
}

CachedStockLevel cachedLevel(
  String itemId,
  String binId, {
  double qty = 0,
  int version = 0,
}) =>
    CachedStockLevel(
      inventoryItemId: itemId,
      binId: binId,
      quantityOnHand: qty,
      version: version,
      updatedAtUtc: DateTime.utc(2026, 1, 1),
    );

final _invT0 = DateTime.utc(2026, 1, 1);

InventoryItemSync itemSync(
  String id, {
  String sku = 'SKU',
  String name = 'Item',
  String companyId = 'co1',
  String? barcode,
  String? category,
  String? unitOfMeasure,
  bool isActive = true,
}) =>
    InventoryItemSync(
      id: id,
      tenantId: 'tn1',
      companyId: companyId,
      sku: sku,
      name: name,
      isActive: isActive,
      createdAtUtc: _invT0,
      barcode: barcode,
      category: category,
      unitOfMeasure: unitOfMeasure,
    );

StockLevelSync stockLevelSync(
  String id, {
  required String inventoryItemId,
  required String binId,
  double quantityOnHand = 0,
  int version = 0,
  String companyId = 'co1',
}) =>
    StockLevelSync(
      id: id,
      inventoryItemId: inventoryItemId,
      binId: binId,
      rackId: 'r1',
      warehouseId: 'w1',
      locationId: 'l1',
      companyId: companyId,
      tenantId: 'tn1',
      quantityOnHand: quantityOnHand,
      version: version,
      createdAtUtc: _invT0,
    );

/// In-memory [InventoryLocalDataSource] mirroring the SQLite behaviour the read
/// path + sync engine rely on: id-keyed item upsert, (item,bin)-keyed stock
/// upsert, a LEFT-JOIN aggregate on-hand (0 when an item has no stock rows), a
/// case-insensitive substring search over sku/name/barcode, one metadata row
/// per entity, and cursor advancement **only** from a non-null nextCursor. No
/// platform channel / real DB needed — same approach as
/// `FakeHierarchyLocalDataSource`.
class FakeInventoryLocalDataSource implements InventoryLocalDataSource {
  final Map<String, Map<String, Object?>> _items = {}; // id -> row
  final Map<String, Map<String, Object?>> _stock = {}; // 'item|bin' -> row
  final Map<String, SyncMetadata> _meta = {};
  Set<String> _snapshot = {};

  int reachableReplacements = 0;

  static String _stockKey(String itemId, String binId) => '$itemId|$binId';

  // ---- Test helpers ---------------------------------------------------------

  void seedItem(InventoryItemSync item) => _items[item.id] = item.toRow();

  void seedStock(StockLevelSync level) =>
      _stock[_stockKey(level.inventoryItemId, level.binId)] = level.toCacheRow();

  void seedMetadata(SyncMetadata meta) => _meta[meta.entity] = meta;

  void seedSnapshot(Set<String> ids) => _snapshot = {...ids};

  int itemCount() => _items.length;

  int stockCount() => _stock.length;

  SyncMetadata? metaOf(String entity) => _meta[entity];

  // ---- Read path ------------------------------------------------------------

  double _totalFor(String id) => _stock.values
      .where((s) => s['inventory_item_id'] == id)
      .fold<double>(0, (sum, s) => sum + (s['quantity_on_hand'] as num).toDouble());

  @override
  Future<List<InventoryItem>> aggregateItems({String? search}) async {
    final term = search?.trim().toLowerCase();
    bool matches(Map<String, Object?> row) {
      if (term == null || term.isEmpty) return true;
      final sku = (row['sku'] as String).toLowerCase();
      final name = (row['name'] as String).toLowerCase();
      final barcode = (row['barcode'] as String?)?.toLowerCase();
      return sku.contains(term) ||
          name.contains(term) ||
          (barcode != null && barcode.contains(term));
    }

    return _items.values.where(matches).map((row) {
      final id = row['id'] as String;
      return InventoryItem(
        id: id,
        sku: row['sku'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) != 0,
        totalQuantityOnHand: _totalFor(id),
        barcode: row['barcode'] as String?,
        unitOfMeasure: row['unit_of_measure'] as String?,
        category: row['category'] as String?,
      );
    }).toList(growable: false);
  }

  @override
  Future<InventoryItemDetail?> getItemById(String id) async {
    final row = _items[id];
    if (row == null) return null;
    final bins = _stock.values
        .where((s) => s['inventory_item_id'] == id)
        .map((s) => StockByBin(
              binId: s['bin_id'] as String,
              quantityOnHand: (s['quantity_on_hand'] as num).toDouble(),
              version: s['version'] as int,
            ))
        .toList()
      ..sort((a, b) => a.binId.compareTo(b.binId));
    final total = bins.fold<double>(0, (sum, b) => sum + b.quantityOnHand);
    return InventoryItemDetail(
      id: row['id'] as String,
      sku: row['sku'] as String,
      name: row['name'] as String,
      isActive: (row['is_active'] as int) != 0,
      totalQuantityOnHand: total,
      stockByBin: bins,
      movements: const [],
      tenantId: row['tenant_id'] as String?,
      companyId: row['company_id'] as String?,
      barcode: row['barcode'] as String?,
      description: row['description'] as String?,
      unitOfMeasure: row['unit_of_measure'] as String?,
      category: row['category'] as String?,
    );
  }

  // ---- Sync upserts ---------------------------------------------------------

  @override
  Future<void> upsertPageAndAdvanceCursor({
    required String table,
    required String entity,
    required List<Map<String, Object?>> rows,
    required String? nextCursor,
  }) async {
    for (final row in rows) {
      if (table == 'inventory_item') {
        _items[row['id'] as String] = row;
      } else if (table == 'stock_version_cache') {
        _stock[_stockKey(
            row['inventory_item_id'] as String, row['bin_id'] as String)] = row;
      } else {
        throw ArgumentError('Unknown table: $table');
      }
    }
    if (nextCursor != null) {
      final existing = _meta[entity] ?? SyncMetadata(entity: entity);
      _meta[entity] = existing.copyWith(lastCursor: nextCursor);
    }
  }

  // ---- Metadata -------------------------------------------------------------

  @override
  Future<SyncMetadata?> readSyncMetadata(String entity) async => _meta[entity];

  @override
  Future<void> writeSyncMetadata(SyncMetadata meta) async =>
      _meta[meta.entity] = meta;

  // ---- Snapshot -------------------------------------------------------------

  @override
  Future<Set<String>> readReachableSnapshot() async => {..._snapshot};

  @override
  Future<void> replaceReachableSnapshot(Set<String> companyIds) async {
    _snapshot = {...companyIds};
    reachableReplacements++;
  }
}
