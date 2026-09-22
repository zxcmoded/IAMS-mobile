import 'package:equatable/equatable.dart';

/// A company in the master-data hierarchy — the root level.
///
/// Carries the API shape (`fromJson`/`toJson`, camelCase, ISO-8601 timestamps)
/// and the SQLite row shape (`fromRow`/`toRow`, snake_case columns, `isActive`
/// stored as `0`/`1`, timestamps as ISO-8601 strings). `updatedAtUtc` is
/// nullable server-side; everything else is non-null.
class Company extends Equatable {
  const Company({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAtUtc,
    this.updatedAtUtc,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAtUtc;
  final DateTime? updatedAtUtc;

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        updatedAtUtc: json['updatedAtUtc'] == null
            ? null
            : DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'updatedAtUtc': updatedAtUtc?.toIso8601String(),
      };

  factory Company.fromRow(Map<String, Object?> row) => Company(
        id: row['id'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) != 0,
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
        updatedAtUtc: row['updated_at_utc'] == null
            ? null
            : DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'is_active': isActive ? 1 : 0,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'updated_at_utc': updatedAtUtc?.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, name, isActive, createdAtUtc, updatedAtUtc];
}
