import 'package:iams_mobile/core/storage/device_id_provider.dart';
import 'package:iams_mobile/features/inventory/data/models/cached_stock_level.dart';
import 'package:iams_mobile/features/inventory/data/models/inventory_enums.dart';
import 'package:iams_mobile/features/inventory/data/models/outbox_entry.dart';
import 'package:iams_mobile/features/inventory/data/outbox_local_data_source.dart';

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
