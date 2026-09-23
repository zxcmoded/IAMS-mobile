import 'package:equatable/equatable.dart';

/// One SKU line of a locally-created [InventoryRecord] — a resolved
/// inventory_item id, its `sku` (the value scanned/entered), a denormalized
/// `name` for offline display, and the accumulated [quantity]. Repeated scans of
/// the same SKU within a session collapse onto a single line (the quantity
/// accumulates) rather than producing duplicate lines.
class InventoryRecordLine extends Equatable {
  const InventoryRecordLine({
    required this.inventoryItemId,
    required this.sku,
    required this.name,
    required this.quantity,
  });

  final String inventoryItemId;
  final String sku;
  final String name;
  final double quantity;

  InventoryRecordLine copyWith({double? quantity}) => InventoryRecordLine(
        inventoryItemId: inventoryItemId,
        sku: sku,
        name: name,
        quantity: quantity ?? this.quantity,
      );

  /// The sync-facing shape (matches the spec's `items[]` element: `sku` +
  /// `quantity`). `inventoryItemId`/`name` are carried too so a future sync can
  /// resolve without another local lookup.
  Map<String, dynamic> toJson() => {
        'inventoryItemId': inventoryItemId,
        'sku': sku,
        'name': name,
        'quantity': quantity,
      };

  factory InventoryRecordLine.fromRow(Map<String, Object?> row) =>
      InventoryRecordLine(
        inventoryItemId: row['inventory_item_id'] as String,
        sku: row['sku'] as String,
        name: row['item_name'] as String,
        quantity: (row['quantity'] as num).toDouble(),
      );

  Map<String, Object?> toRow(String recordId) => {
        'record_id': recordId,
        'inventory_item_id': inventoryItemId,
        'sku': sku,
        'item_name': name,
        'quantity': quantity,
      };

  @override
  List<Object?> get props => [inventoryItemId, sku, name, quantity];
}

/// A locally-created physical inventory / cycle-count **session** — a warehouse
/// (required), an optional rack and bin, and a list of SKU/quantity [items].
///
/// This is a **new, local-only** entity, distinct from the synced `InventoryItem`
/// master and the outbox-backed stock-count mutation. Every record created on
/// the device is stamped [isOffline] `= true` and has **no sync path yet** (a
/// future Sync feature will find `isOffline = true` records). This code never
/// flips [isOffline] to `false`.
///
/// Denormalized `*Name` fields are stored alongside the ids so the offline
/// records list renders human-readable labels with zero further lookups.
class InventoryRecord extends Equatable {
  const InventoryRecord({
    required this.id,
    required this.warehouseId,
    required this.warehouseName,
    required this.items,
    this.rackId,
    this.rackName,
    this.binId,
    this.binName,
    this.isOffline = true,
    required this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String warehouseId;
  final String warehouseName;
  final String? rackId;
  final String? rackName;
  final String? binId;
  final String? binName;
  final List<InventoryRecordLine> items;

  /// Always `true` for records created on-device; used by the future Sync
  /// feature. Never set to `false` by this code.
  final bool isOffline;

  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;

  double get totalQuantity =>
      items.fold<double>(0, (sum, l) => sum + l.quantity);

  /// The sync-facing shape, matching the spec example
  /// (`id`, `warehouseId`, `rackId`, `binId`, `items[]`, `isOffline`).
  Map<String, dynamic> toJson() => {
        'id': id,
        'warehouseId': warehouseId,
        'rackId': rackId,
        'binId': binId,
        'items': items.map((l) => l.toJson()).toList(growable: false),
        'isOffline': isOffline,
      };

  Map<String, Object?> toRow() => {
        'id': id,
        'warehouse_id': warehouseId,
        'warehouse_name': warehouseName,
        'rack_id': rackId,
        'rack_name': rackName,
        'bin_id': binId,
        'bin_name': binName,
        'is_offline': isOffline ? 1 : 0,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
      };

  factory InventoryRecord.fromRow(
    Map<String, Object?> row,
    List<InventoryRecordLine> items,
  ) =>
      InventoryRecord(
        id: row['id'] as String,
        warehouseId: row['warehouse_id'] as String,
        warehouseName: row['warehouse_name'] as String,
        rackId: row['rack_id'] as String?,
        rackName: row['rack_name'] as String?,
        binId: row['bin_id'] as String?,
        binName: row['bin_name'] as String?,
        items: items,
        isOffline: (row['is_offline'] as int) != 0,
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
        updatedAtUtc: row['updated_at_utc'] == null
            ? null
            : DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      );

  @override
  List<Object?> get props => [
        id,
        warehouseId,
        warehouseName,
        rackId,
        rackName,
        binId,
        binName,
        items,
        isOffline,
        createdAtUtc,
        updatedAtUtc,
      ];
}
