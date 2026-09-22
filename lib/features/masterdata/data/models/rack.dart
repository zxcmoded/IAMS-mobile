import 'package:equatable/equatable.dart';

/// A rack under a [Warehouse]. Carries its denormalized ancestor ids
/// (`warehouseId`, `locationId`, `companyId`) directly off the row.
class Rack extends Equatable {
  const Rack({
    required this.id,
    required this.warehouseId,
    required this.locationId,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String warehouseId;
  final String locationId;
  final String companyId;
  final String name;
  final bool isActive;
  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;

  factory Rack.fromJson(Map<String, dynamic> json) => Rack(
        id: json['id'] as String,
        warehouseId: json['warehouseId'] as String,
        locationId: json['locationId'] as String,
        companyId: json['companyId'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        updatedAtUtc: json['updatedAtUtc'] == null
            ? null
            : DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'warehouseId': warehouseId,
        'locationId': locationId,
        'companyId': companyId,
        'name': name,
        'isActive': isActive,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'updatedAtUtc': updatedAtUtc?.toIso8601String(),
      };

  factory Rack.fromRow(Map<String, Object?> row) => Rack(
        id: row['id'] as String,
        warehouseId: row['warehouse_id'] as String,
        locationId: row['location_id'] as String,
        companyId: row['company_id'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) != 0,
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
        updatedAtUtc: row['updated_at_utc'] == null
            ? null
            : DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'warehouse_id': warehouseId,
        'location_id': locationId,
        'company_id': companyId,
        'name': name,
        'is_active': isActive ? 1 : 0,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id,
        warehouseId,
        locationId,
        companyId,
        name,
        isActive,
        createdAtUtc,
        updatedAtUtc,
      ];
}
