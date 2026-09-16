import 'package:equatable/equatable.dart';

/// A location under a [Company]. `region` is nullable server-side.
class Location extends Equatable {
  const Location({
    required this.id,
    required this.tenantId,
    required this.companyId,
    required this.name,
    required this.isActive,
    required this.createdAtUtc,
    this.updatedAtUtc,
    this.region,
  });

  final String id;
  final String tenantId;
  final String companyId;
  final String name;
  final bool isActive;
  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;
  final String? region;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
        id: json['id'] as String,
        tenantId: json['tenantId'] as String,
        companyId: json['companyId'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        updatedAtUtc: json['updatedAtUtc'] == null
            ? null
            : DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
        region: json['region'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenantId': tenantId,
        'companyId': companyId,
        'name': name,
        'isActive': isActive,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'updatedAtUtc': updatedAtUtc?.toIso8601String(),
        'region': region,
      };

  factory Location.fromRow(Map<String, Object?> row) => Location(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        companyId: row['company_id'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) != 0,
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
        updatedAtUtc: row['updated_at_utc'] == null
            ? null
            : DateTime.parse(row['updated_at_utc'] as String).toUtc(),
        region: row['region'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'tenant_id': tenantId,
        'company_id': companyId,
        'name': name,
        'region': region,
        'is_active': isActive ? 1 : 0,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        id,
        tenantId,
        companyId,
        name,
        isActive,
        createdAtUtc,
        updatedAtUtc,
        region,
      ];
}
