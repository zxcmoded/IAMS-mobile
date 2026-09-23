import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'audit_qty_format.dart';
import 'models/audit_record.dart';

/// Pure-Dart encoders that turn stored [AuditRecord]s (or the sample template)
/// into CSV text / XLSX bytes with the spec's exact column structure
/// (`Warehouse, Rack, Bin, SKU, Qty`). Kept free of any file/plugin I/O so the
/// column structure is unit-testable — the `csv`/`excel` codecs are pure Dart
/// and run under `flutter test`; only the write-to-disk + share step
/// (`AuditFileService`) touches plugins.
class AuditExportEncoder {
  const AuditExportEncoder._();

  static final DateTime _sampleStamp = DateTime.utc(2026, 1, 1);

  /// The sample template content: the two illustrative example rows from the
  /// spec (rendered on top of the shared header row).
  static final List<AuditRecord> templateRecords = [
    AuditRecord(
      id: 'sample-1',
      warehouse: 'WH-001',
      rack: 'RACK-01',
      bin: 'BIN-001',
      sku: 'SKU-10001',
      qty: 10,
      createdAtUtc: _sampleStamp,
    ),
    AuditRecord(
      id: 'sample-2',
      warehouse: 'WH-001',
      rack: 'RACK-01',
      bin: 'BIN-002',
      sku: 'SKU-10002',
      qty: 25,
      createdAtUtc: _sampleStamp,
    ),
  ];

  /// The full table (header row + one row per record), all cells stringified,
  /// in [AuditRecord.columns] order. Optional fields render as empty strings.
  static List<List<String>> toRows(List<AuditRecord> records) => [
        AuditRecord.columns,
        for (final r in records)
          [
            r.warehouse,
            r.rack ?? '',
            r.bin ?? '',
            r.sku,
            formatAuditQty(r.qty),
          ],
      ];

  /// CSV text for [records] (header + data rows).
  static String toCsv(List<AuditRecord> records) =>
      const ListToCsvConverter().convert(toRows(records));

  /// XLSX bytes for [records]: a header row of text cells plus one row per
  /// record, with Qty written as a real numeric cell so spreadsheet software
  /// treats it as a number.
  static List<int> toXlsx(List<AuditRecord> records) {
    final workbook = Excel.createExcel();
    final sheetName = workbook.getDefaultSheet()!;

    workbook.appendRow(sheetName,
        AuditRecord.columns.map<CellValue?>((c) => TextCellValue(c)).toList());
    for (final r in records) {
      workbook.appendRow(sheetName, <CellValue?>[
        TextCellValue(r.warehouse),
        TextCellValue(r.rack ?? ''),
        TextCellValue(r.bin ?? ''),
        TextCellValue(r.sku),
        DoubleCellValue(r.qty),
      ]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Failed to generate the .xlsx workbook.');
    }
    return bytes;
  }
}
