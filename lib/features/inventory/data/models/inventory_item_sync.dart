import 'package:equatable/equatable.dart';

/// One `InventoryItem` master row from `GET /inventory/sync/items`
/// (`InventoryItemSyncDto`), on its way into the local `inventory_item` table.
///
/// Carries the API shape (`fromJson`, camelCase, ISO-8601 timestamps) and the
/// SQLite row shape (`toRow`, snake_case columns, `isActive` as `0`/`1`).
/// `barcode`/`description`/`unitOfMeasure`/`category`/`updatedAtUtc` are
/// nullable; everything else is non-null. Inactive rows (`isActive == false`)
/// are still delivered and upserted — soft deletes converge locally, never a
/// hard-delete-on-absence.
class InventoryItemSync extends Equatable {
  const InventoryItemSync({
    required this.id,
    required this.tenantId,
    required this.companyId,
    required this.sku,
    required this.name,
    required this.isActive,
    required this.createdAtUtc,
    this.barcode,
    this.description,
    this.unitOfMeasure,
    this.category,
    this.updatedAtUtc,
  });

  final String id;
  final String tenantId;
  final String companyId;
  final String sku;
  final String name;
  final bool isActive;
  final DateTime createdAtUtc;
  final String? barcode;
  final String? description;
  final String? unitOfMeasure;
  final String? category;
  final DateTime? updatedAtUtc;

  factory InventoryItemSync.fromJson(Map<String, dynamic> json) =>
      InventoryItemSync(
        id: json['id'] as String,
        tenantId: json['tenantId'] as String,
        companyId: json['companyId'] as String,
        sku: json['sku'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool? ?? true,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        barcode: json['barcode'] as String?,
        description: json['description'] as String?,
        unitOfMeasure: json['unitOfMeasure'] as String?,
        category: json['category'] as String?,
        updatedAtUtc: json['updatedAtUtc'] == null
            ? null
            : DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'tenant_id': tenantId,
        'company_id': companyId,
        'sku': sku,
        'barcode': barcode,
        'name': name,
        'description': description,
        'unit_of_measure': unitOfMeasure,
        'category': category,
        'is_active': isActive ? 1 : 0,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id,
        tenantId,
        companyId,
        sku,
        name,
        isActive,
        createdAtUtc,
        barcode,
        description,
        unitOfMeasure,
        category,
        updatedAtUtc,
      ];
}
