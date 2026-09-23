import 'package:equatable/equatable.dart';

import 'models/inventory_enums.dart';
import 'models/inventory_item.dart';
import 'models/inventory_item_detail.dart';
import 'models/outbox_entry.dart';
import 'inventory_local_data_source.dart';
import 'outbox_local_data_source.dart';

/// The dashboard's local-only "Inventory Summary" — total active SKUs and the
/// synced/unsynced split, all derived from local SQLite (no API call).
class InventorySummary extends Equatable {
  const InventorySummary({
    required this.totalSkus,
    required this.syncedCount,
    required this.unsyncedCount,
  });

  /// Count of active `inventory_item` rows.
  final int totalSkus;

  /// Items with **no** pending/failed outbox mutation (`totalSkus - unsynced`,
  /// floored at 0).
  final int syncedCount;

  /// Items with at least one pending/failed outbox mutation — i.e. changes not
  /// yet accepted by the server.
  final int unsyncedCount;

  @override
  List<Object?> get props => [totalSkus, syncedCount, unsyncedCount];
}

/// The default inclusive upper bound for the `low_stock` filter, matching the
/// backend's `InventoryDefaults.DefaultLowStockThreshold` (10) so the offline
/// list classifies items exactly as the server's `ListInventory` did.
const double kDefaultLowStockThreshold = 10;

/// Read-only, **local-only** access to inventory for the UI. Constructed with
/// only the two local data sources — it holds no API client, so a screen
/// reading through this repository physically cannot reach the network (the
/// same guarantee `HierarchyRepository` gives). All inventory API traffic lives
/// in `InventorySyncService` / `OutboxRepository`.
///
/// The list/detail views are computed entirely from SQLite: the `inventory_item`
/// master joined against `stock_version_cache` for aggregate on-hand, with
/// pending-outbox deltas overlaid so a just-queued mutation is reflected
/// immediately. Search / filter / sort / pagination match the server's old
/// `ListInventory` semantics exactly (case-insensitive substring over
/// sku/name/barcode; filter over *effective* total on-hand; `ORDER BY sku, id`;
/// offset pagination with a peek-ahead `hasMore`).
class InventoryRepository {
  InventoryRepository(this._local, this._outbox);

  final InventoryLocalDataSource _local;
  final OutboxLocalDataSource _outbox;

  /// One page of the local inventory list. [page] is 1-based.
  Future<InventoryPage> getList({
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
    double lowStockThreshold = kDefaultLowStockThreshold,
    int page = 1,
    int pageSize = 50,
  }) async {
    final base = await _local.aggregateItems(
      search: search.isEmpty ? null : search,
    );
    final deltas = await _pendingItemDeltas();

    // Overlay pending deltas onto the confirmed aggregate, then classify on the
    // *effective* total so list and detail agree.
    final effective = base
        .map((i) => deltas.containsKey(i.id)
            ? i.copyWith(
                totalQuantityOnHand: i.totalQuantityOnHand + deltas[i.id]!)
            : i)
        .where((i) => _matchesFilter(i, filter, lowStockThreshold))
        .toList()
      ..sort(_bySkuThenId);

    final start = (page - 1) * pageSize;
    final slice =
        effective.skip(start < 0 ? 0 : start).take(pageSize + 1).toList();
    final hasMore = slice.length > pageSize;
    final items = hasMore ? slice.take(pageSize).toList(growable: false) : slice;

    return InventoryPage(
      items: items,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// The dashboard's "Inventory Summary" — computed entirely from local SQLite.
  /// "Unsynced" is the number of distinct items carrying a `pending`/`failed`
  /// outbox row; the rest of the active SKUs are "synced". The subtraction is
  /// floored at 0 so a stray outbox row for an item no longer in the active
  /// cache can never produce a negative synced count.
  Future<InventorySummary> loadSummary() async {
    final total = await _local.countActiveItems();
    final unsyncedIds = await _outbox.itemIdsWithStatus(
      const [OutboxStatus.pending, OutboxStatus.failed],
    );
    final unsynced = unsyncedIds.length;
    final synced = total - unsynced;
    return InventorySummary(
      totalSkus: total,
      syncedCount: synced < 0 ? 0 : synced,
      unsyncedCount: unsynced,
    );
  }

  /// The item detail built from local tables (`null` = not in the local cache,
  /// i.e. not in the accessible/synced scope). Movement history is always empty
  /// locally (`InventoryTransactions` sync is out of scope).
  Future<InventoryItemDetail?> getItemDetail(String id) =>
      _local.getItemById(id);

  /// Resolves a scanned/entered SKU or barcode to its item using only the local
  /// `inventory_item` cache (no API). `null` = the code matches no known item
  /// (an invalid SKU). Used by the offline Create-Inventory flow to validate a
  /// SKU before adding it to a record.
  Future<InventoryItem?> findItemByCode(String code) =>
      _local.findItemByCode(code);

  // ---- Pending overlay ------------------------------------------------------

  /// Net per-item on-hand delta from all `pending`/`conflict` outbox rows
  /// (transfers net to zero per item; counts contribute nothing — an absolute
  /// set whose outcome the server adjudicates).
  Future<Map<String, double>> _pendingItemDeltas() async {
    final entries = await _outbox.getOverlayEntries();
    final deltas = <String, double>{};
    for (final e in entries) {
      final net = _netItemDelta(e);
      if (net != 0) {
        deltas[e.inventoryItemId] = (deltas[e.inventoryItemId] ?? 0) + net;
      }
    }
    return deltas;
  }

  double _netItemDelta(OutboxEntry e) =>
      e.pendingBinDeltas().values.fold<double>(0, (sum, d) => sum + d);

  // ---- Filter / sort --------------------------------------------------------

  bool _matchesFilter(
    InventoryItem item,
    InventoryFilter filter,
    double lowStockThreshold,
  ) {
    final total = item.totalQuantityOnHand;
    switch (filter) {
      case InventoryFilter.all:
        return true;
      case InventoryFilter.inStock:
        return total > 0;
      case InventoryFilter.outOfStock:
        return total <= 0;
      case InventoryFilter.lowStock:
        return total > 0 && total <= lowStockThreshold;
    }
  }

  int _bySkuThenId(InventoryItem a, InventoryItem b) {
    final bySku = a.sku.toLowerCase().compareTo(b.sku.toLowerCase());
    return bySku != 0 ? bySku : a.id.compareTo(b.id);
  }
}
