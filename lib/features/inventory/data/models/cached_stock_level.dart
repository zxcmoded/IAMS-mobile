import 'package:equatable/equatable.dart';

/// The last-observed authoritative on-hand + version for one (item, bin) pair,
/// persisted in `stock_version_cache`. Two jobs:
///
/// 1. **Conflict basis** — the [version] stamped as `base*StockVersion` when a
///    queued offline mutation is replayed, so a concurrent server change
///    surfaces as `409 stock_version_conflict`.
/// 2. **Optimistic display** — [quantityOnHand] is nudged locally the moment a
///    delta-based mutation (receive/transfer/adjust) is committed, so the UI
///    reflects the pending change while offline; it is overwritten with the
///    server's authoritative value on reconcile.
class CachedStockLevel extends Equatable {
  const CachedStockLevel({
    required this.inventoryItemId,
    required this.binId,
    required this.quantityOnHand,
    required this.version,
    required this.updatedAtUtc,
  });

  final String inventoryItemId;
  final String binId;
  final double quantityOnHand;
  final int version;
  final DateTime updatedAtUtc;

  CachedStockLevel copyWith({double? quantityOnHand, int? version}) =>
      CachedStockLevel(
        inventoryItemId: inventoryItemId,
        binId: binId,
        quantityOnHand: quantityOnHand ?? this.quantityOnHand,
        version: version ?? this.version,
        updatedAtUtc: DateTime.now().toUtc(),
      );

  factory CachedStockLevel.fromRow(Map<String, Object?> row) =>
      CachedStockLevel(
        inventoryItemId: row['inventory_item_id'] as String,
        binId: row['bin_id'] as String,
        quantityOnHand: (row['quantity_on_hand'] as num).toDouble(),
        version: row['version'] as int,
        updatedAtUtc: DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      );

  Map<String, Object?> toRow() => {
        'inventory_item_id': inventoryItemId,
        'bin_id': binId,
        'quantity_on_hand': quantityOnHand,
        'version': version,
        'updated_at_utc': updatedAtUtc.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [inventoryItemId, binId, quantityOnHand, version, updatedAtUtc];
}
