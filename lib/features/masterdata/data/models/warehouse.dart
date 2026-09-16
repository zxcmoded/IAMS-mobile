import 'package:equatable/equatable.dart';

/// A warehouse under a [Location]. Carries its denormalized ancestor ids
/// (`locationId`, `companyId`) directly off the row — no joins needed.
class Warehouse extends Equatable {
  const Warehouse({
    required this.id,
    required this.tenantId,
    required this.locationId,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String tenantId;
  final String locationId;
  final String companyId;
  final String name;
  final bool isActive;
  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        tenantId: json['tenantId'] as String,
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
        'tenantId': tenantId,
        'locationId': locationId,
        'companyId': companyId,
        'name': name,
        'isActive': isActive,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'updatedAtUtc': updatedAtUtc?.toIso8601String(),
      };

  factory Warehouse.fromRow(Map<String, Object?> row) => Warehouse(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
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
        'tenant_id': tenantId,
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
        tenantId,
        locationId,
        companyId,
        name,
        isActive,
        createdAtUtc,
        updatedAtUtc,
      ];
}
