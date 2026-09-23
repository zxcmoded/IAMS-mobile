import 'package:equatable/equatable.dart';

/// A single audit row — the fully-offline Audit feature's core entity, matching
/// the spec's column structure exactly: Warehouse (required), Rack (optional),
/// Bin (optional), SKU (required), Qty (required, non-negative).
///
/// This is a flat value with no master-data references: it is populated verbatim
/// from a user-supplied CSV/XLSX import and exported back to the same shape, so
/// it never resolves against the hierarchy or the `inventory_item` master.
class AuditRecord extends Equatable {
  const AuditRecord({
    required this.id,
    required this.warehouse,
    required this.sku,
    required this.qty,
    this.rack,
    this.bin,
    required this.createdAtUtc,
  });

  final String id;
  final String warehouse;
  final String? rack;
  final String? bin;
  final String sku;
  final double qty;
  final DateTime createdAtUtc;

  /// The canonical column order used by every export/template writer and by the
  /// import parser's header. Kept in one place so CSV and XLSX stay identical.
  static const List<String> columns = ['Warehouse', 'Rack', 'Bin', 'SKU', 'Qty'];

  /// The row rendered as export cells, in [columns] order. Optional fields
  /// render as an empty string (never the literal "null").
  List<Object?> toExportCells() => [
        warehouse,
        rack ?? '',
        bin ?? '',
        sku,
        qty,
      ];

  Map<String, Object?> toRow() => {
        'id': id,
        'warehouse': warehouse,
        'rack': rack,
        'bin': bin,
        'sku': sku,
        'qty': qty,
        'created_at_utc': createdAtUtc.toIso8601String(),
      };

  factory AuditRecord.fromRow(Map<String, Object?> row) => AuditRecord(
        id: row['id'] as String,
        warehouse: row['warehouse'] as String,
        rack: row['rack'] as String?,
        bin: row['bin'] as String?,
        sku: row['sku'] as String,
        qty: (row['qty'] as num).toDouble(),
        createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
      );

  @override
  List<Object?> get props => [id, warehouse, rack, bin, sku, qty, createdAtUtc];
}
