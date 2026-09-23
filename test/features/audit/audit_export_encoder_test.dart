import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/audit/data/audit_export_encoder.dart';
import 'package:iams_mobile/features/audit/data/audit_import_parser.dart';
import 'package:iams_mobile/features/audit/data/models/audit_record.dart';

import '../../support/audit_fixtures.dart';

void main() {
  const expectedHeader = ['Warehouse', 'Rack', 'Bin', 'SKU', 'Qty'];

  test('AuditRecord.columns is the spec column structure', () {
    expect(AuditRecord.columns, expectedHeader);
  });

  group('CSV export', () {
    test('first row is the header in spec order', () {
      final rows = AuditExportEncoder.toRows([
        auditRecord('1', warehouse: 'WH-1', rack: 'R1', bin: 'B1', sku: 'S1', qty: 3),
      ]);
      expect(rows.first, expectedHeader);
    });

    test('emits one row per record with cells in column order', () {
      final rows = AuditExportEncoder.toRows([
        auditRecord('1',
            warehouse: 'WH-1', rack: 'R1', bin: 'B1', sku: 'S1', qty: 3),
        auditRecord('2',
            warehouse: 'WH-2', rack: null, bin: null, sku: 'S2', qty: 25),
      ]);
      expect(rows, hasLength(3)); // header + 2 records
      expect(rows[1], ['WH-1', 'R1', 'B1', 'S1', '3']);
      // Optional fields render as empty strings, whole qty has no trailing .0.
      expect(rows[2], ['WH-2', '', '', 'S2', '25']);
    });

    test('CSV text round-trips back to the same columns', () {
      final csv = AuditExportEncoder.toCsv([
        auditRecord('1',
            warehouse: 'WH-1', rack: 'R1', bin: 'B1', sku: 'S1', qty: 3),
      ]);
      final parsed = const CsvToListConverter(shouldParseNumbers: false)
          .convert(csv);
      expect(parsed.first, expectedHeader);
      expect(parsed[1], ['WH-1', 'R1', 'B1', 'S1', '3']);
    });
  });

  group('XLSX export', () {
    test('bytes decode back to the spec header + record rows', () {
      final bytes = AuditExportEncoder.toXlsx([
        auditRecord('1',
            warehouse: 'WH-1', rack: 'R1', bin: 'B1', sku: 'S1', qty: 3),
        auditRecord('2',
            warehouse: 'WH-2', rack: null, bin: null, sku: 'S2', qty: 25),
      ]);

      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook.tables[workbook.getDefaultSheet()!]!;
      final header =
          sheet.rows.first.map((c) => c?.value.toString()).toList();
      expect(header, expectedHeader);

      final row1 = sheet.rows[1].map((c) => c?.value.toString()).toList();
      expect(row1[0], 'WH-1');
      expect(row1[3], 'S1');
      // Qty is a real numeric cell (excel normalizes a whole double to an int
      // cell on decode — the point is it's numeric, not text).
      final qtyCell = sheet.rows[1][4]!.value;
      expect(qtyCell, anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()));
      expect(qtyCell.toString(), '3');
    });

    test('XLSX export round-trips through the import parser', () {
      final bytes = AuditExportEncoder.toXlsx([
        auditRecord('1',
            warehouse: 'WH-1', rack: 'R1', bin: 'B1', sku: 'S1', qty: 3),
      ]);
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook.tables[workbook.getDefaultSheet()!]!;
      final table = sheet.rows
          .map((row) => row.map((cell) => cell?.value).toList())
          .toList();

      final result = AuditImportParser.parse(table);
      expect(result.hasFileError, isFalse);
      expect(result.validRecords, hasLength(1));
      final r = result.validRecords.single;
      expect(r.warehouse, 'WH-1');
      expect(r.sku, 'S1');
      expect(r.qty, 3);
    });
  });

  group('sample template', () {
    test('contains header + the two spec example rows', () {
      final rows = AuditExportEncoder.toRows(AuditExportEncoder.templateRecords);
      expect(rows.first, expectedHeader);
      expect(rows[1], ['WH-001', 'RACK-01', 'BIN-001', 'SKU-10001', '10']);
      expect(rows[2], ['WH-001', 'RACK-01', 'BIN-002', 'SKU-10002', '25']);
    });
  });
}
