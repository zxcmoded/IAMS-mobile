import 'package:equatable/equatable.dart';

/// One `StockLevel` (per item-per-bin on-hand) row from
/// `GET /inventory/sync/stock-levels` (`StockLevelSyncDto`), on its way into the
/// local `stock_version_cache` table.
///
/// The feed carries full denormalized ancestry (bin → rack → warehouse →
/// location → company), but the local cache only needs
/// `(inventoryItemId, binId) → quantityOnHand, version` — the same shape the
/// outbox mutation flow already reconciles into and stamps `base*StockVersion`
/// from. So [toCacheRow] projects onto exactly those columns; the ancestry ids
/// are retained on the DTO for parity/validation but not persisted (rack/
/// warehouse/location for the detail view come from the local `hierarchy`
/// tables, joined by bin id, not denormalized a second time here).
///
/// [version] is the app-managed monotonic counter (`long` on the wire → `int`
/// locally) — the same value the mutation endpoints return and the conflict
/// check rides on. `quantityOnHand` is a `decimal` on the wire → `double`
/// locally. `updatedAtUtc` is nullable on the wire; the cache column is
/// non-null, so it falls back to [createdAtUtc].
class StockLevelSync extends Equatable {
  const StockLevelSync({
    required this.id,
    required this.inventoryItemId,
    required this.binId,
    required this.rackId,
    required this.warehouseId,
    required this.locationId,
    required this.companyId,
    required this.quantityOnHand,
    required this.version,
    required this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String inventoryItemId;
  final String binId;
  final String rackId;
  final String warehouseId;
  final String locationId;
  final String companyId;
  final double quantityOnHand;
  final int version;
  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;

  factory StockLevelSync.fromJson(Map<String, dynamic> json) => StockLevelSync(
        id: json['id'] as String,
        inventoryItemId: json['inventoryItemId'] as String,
        binId: json['binId'] as String,
        rackId: json['rackId'] as String,
        warehouseId: json['warehouseId'] as String,
        locationId: json['locationId'] as String,
        companyId: json['companyId'] as String,
        quantityOnHand: (json['quantityOnHand'] as num?)?.toDouble() ?? 0,
        // `version` is a long server-side; Dart ints are 64-bit so `as int` is
        // safe. Tolerate a JSON number just in case.
        version: (json['version'] as num?)?.toInt() ?? 0,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        updatedAtUtc: json['updatedAtUtc'] == null
            ? null
            : DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
      );

  /// Project onto the `stock_version_cache` row shape (the shared reconcile
  /// target). `updated_at_utc` is non-null in that table, so fall back to
  /// `createdAtUtc` when the server omits it.
  Map<String, Object?> toCacheRow() => {
        'inventory_item_id': inventoryItemId,
        'bin_id': binId,
        'quantity_on_hand': quantityOnHand,
        'version': version,
        'updated_at_utc': (updatedAtUtc ?? createdAtUtc).toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id,
        inventoryItemId,
        binId,
        rackId,
        warehouseId,
        locationId,
        companyId,
        quantityOnHand,
        version,
        createdAtUtc,
        updatedAtUtc,
      ];
}
