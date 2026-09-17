import 'package:equatable/equatable.dart';

import 'inventory_enums.dart';

/// Per-bin on-hand for an item, from item-detail `stockByBin[]`. `version` is
/// the stamp the offline outbox observes and later replays as
/// `base*StockVersion` for the concurrency check.
class StockByBin extends Equatable {
  const StockByBin({
    required this.binId,
    required this.quantityOnHand,
    required this.version,
    this.rackId,
    this.warehouseId,
    this.locationId,
    this.companyId,
  });

  final String binId;
  final double quantityOnHand;
  final int version;
  final String? rackId;
  final String? warehouseId;
  final String? locationId;
  final String? companyId;

  factory StockByBin.fromJson(Map<String, dynamic> json) => StockByBin(
        binId: json['binId'] as String,
        quantityOnHand: (json['quantityOnHand'] as num?)?.toDouble() ?? 0,
        version: json['version'] as int? ?? 0,
        rackId: json['rackId'] as String?,
        warehouseId: json['warehouseId'] as String?,
        locationId: json['locationId'] as String?,
        companyId: json['companyId'] as String?,
      );

  @override
  List<Object?> get props =>
      [binId, quantityOnHand, version, rackId, warehouseId, locationId, companyId];
}

/// One movement (ledger) row on the item-detail history (most-recent-first,
/// capped at 50 by the server).
class Movement extends Equatable {
  const Movement({
    required this.id,
    required this.transactionType,
    required this.status,
    required this.quantity,
    required this.createdAtUtc,
    this.sourceBinId,
    this.destinationBinId,
    this.adjustmentReason,
    this.clientCreatedAtUtc,
  });

  final String id;
  final TransactionType transactionType;
  final MovementStatus status;
  final double quantity;
  final DateTime createdAtUtc;
  final String? sourceBinId;
  final String? destinationBinId;
  final String? adjustmentReason;
  final DateTime? clientCreatedAtUtc;

  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
        id: json['id'] as String,
        transactionType:
            TransactionType.fromWire(json['transactionType'] as String?),
        status: MovementStatus.fromWire(json['status'] as String?),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        sourceBinId: json['sourceBinId'] as String?,
        destinationBinId: json['destinationBinId'] as String?,
        adjustmentReason: json['adjustmentReason'] as String?,
        clientCreatedAtUtc: json['clientCreatedAtUtc'] == null
            ? null
            : DateTime.parse(json['clientCreatedAtUtc'] as String).toUtc(),
      );

  @override
  List<Object?> get props => [
        id,
        transactionType,
        status,
        quantity,
        createdAtUtc,
        sourceBinId,
        destinationBinId,
        adjustmentReason,
        clientCreatedAtUtc,
      ];
}

/// Full item detail (`GET /api/inventory/items/{id}`): identity + qty-by-bin +
/// recent movements.
class InventoryItemDetail extends Equatable {
  const InventoryItemDetail({
    required this.id,
    required this.sku,
    required this.name,
    required this.isActive,
    required this.totalQuantityOnHand,
    required this.stockByBin,
    required this.movements,
    this.tenantId,
    this.companyId,
    this.barcode,
    this.description,
    this.unitOfMeasure,
    this.category,
  });

  final String id;
  final String sku;
  final String name;
  final bool isActive;
  final double totalQuantityOnHand;
  final List<StockByBin> stockByBin;
  final List<Movement> movements;
  final String? tenantId;
  final String? companyId;
  final String? barcode;
  final String? description;
  final String? unitOfMeasure;
  final String? category;

  factory InventoryItemDetail.fromJson(Map<String, dynamic> json) =>
      InventoryItemDetail(
        id: json['id'] as String,
        sku: json['sku'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool? ?? true,
        totalQuantityOnHand:
            (json['totalQuantityOnHand'] as num?)?.toDouble() ?? 0,
        stockByBin: (json['stockByBin'] as List<dynamic>? ?? const [])
            .map((e) => StockByBin.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        movements: (json['movements'] as List<dynamic>? ?? const [])
            .map((e) => Movement.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        tenantId: json['tenantId'] as String?,
        companyId: json['companyId'] as String?,
        barcode: json['barcode'] as String?,
        description: json['description'] as String?,
        unitOfMeasure: json['unitOfMeasure'] as String?,
        category: json['category'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        sku,
        name,
        isActive,
        totalQuantityOnHand,
        stockByBin,
        movements,
        tenantId,
        companyId,
        barcode,
        description,
        unitOfMeasure,
        category,
      ];
}
