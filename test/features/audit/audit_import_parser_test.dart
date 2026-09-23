import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/audit/data/audit_import_parser.dart';

void main() {
  // A deterministic id + clock so assertions don't depend on real UUIDs/time.
  var counter = 0;
  String fixedId() => 'id-${counter++}';
  final fixedNow = DateTime.utc(2026, 9, 23, 12);

  AuditImportResult run(List<List<Object?>> rows) =>
      AuditImportParser.parse(rows, idFactory: fixedId, now: fixedNow);

  setUp(() => counter = 0);

  const header = ['Warehouse', 'Rack', 'Bin', 'SKU', 'Qty'];

  group('valid rows', () {
    test('accepts a fully-populated row', () {
      final result = run([
        header,
        ['WH-001', 'RACK-01', 'BIN-001', 'SKU-10001', '10'],
      ]);

      expect(result.hasFileError, isFalse);
      expect(result.rowErrors, isEmpty);
      expect(result.validRecords, hasLength(1));
      final r = result.validRecords.single;
      expect(r.warehouse, 'WH-001');
      expect(r.rack, 'RACK-01');
      expect(r.bin, 'BIN-001');
      expect(r.sku, 'SKU-10001');
      expect(r.qty, 10);
      expect(r.createdAtUtc, fixedNow);
    });

    test('accepts blank optional Rack/Bin as null', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '5'],
      ]);

      expect(result.rowErrors, isEmpty);
      final r = result.validRecords.single;
      expect(r.rack, isNull);
      expect(r.bin, isNull);
    });

    test('accepts zero as a non-negative quantity', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '0'],
      ]);
      expect(result.rowErrors, isEmpty);
      expect(result.validRecords.single.qty, 0);
    });

    test('accepts a decimal quantity', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '2.5'],
      ]);
      expect(result.rowErrors, isEmpty);
      expect(result.validRecords.single.qty, 2.5);
    });

    test('trims surrounding whitespace on values', () {
      final result = run([
        header,
        ['  WH-001 ', ' RACK-01 ', ' ', ' SKU-1 ', ' 7 '],
      ]);
      final r = result.validRecords.single;
      expect(r.warehouse, 'WH-001');
      expect(r.rack, 'RACK-01');
      expect(r.bin, isNull); // whitespace-only optional -> null
      expect(r.sku, 'SKU-1');
      expect(r.qty, 7);
    });
  });

  group('invalid rows are rejected with correct attribution', () {
    test('missing Warehouse', () {
      final result = run([
        header,
        ['', 'RACK-01', 'BIN-001', 'SKU-1', '10'],
      ]);
      expect(result.validRecords, isEmpty);
      expect(result.rowErrors, hasLength(1));
      final err = result.rowErrors.single;
      expect(err.rowNumber, 2); // header is row 1
      expect(err.fieldErrors.map((e) => e.field), contains('Warehouse'));
    });

    test('missing SKU', () {
      final result = run([
        header,
        ['WH-001', '', '', '', '10'],
      ]);
      expect(result.validRecords, isEmpty);
      expect(result.rowErrors.single.fieldErrors.map((e) => e.field),
          contains('SKU'));
    });

    test('missing Qty', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', ''],
      ]);
      final fe = result.rowErrors.single.fieldErrors.single;
      expect(fe.field, 'Qty');
      expect(fe.reason, contains('required'));
    });

    test('non-numeric Qty', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', 'abc'],
      ]);
      final fe = result.rowErrors.single.fieldErrors.single;
      expect(fe.field, 'Qty');
      expect(fe.reason, contains('valid number'));
    });

    test('negative Qty', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '-3'],
      ]);
      final fe = result.rowErrors.single.fieldErrors.single;
      expect(fe.field, 'Qty');
      expect(fe.reason, contains('negative'));
    });

    test('accumulates multiple field errors on one row', () {
      final result = run([
        header,
        ['', '', '', '', '-1'],
      ]);
      final fields =
          result.rowErrors.single.fieldErrors.map((e) => e.field).toSet();
      expect(fields, containsAll(['Warehouse', 'SKU', 'Qty']));
    });

    test('reports correct row numbers across a mixed file', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '1'], // row 2 ok
        ['', '', '', 'SKU-2', '2'], // row 3 bad (warehouse)
        ['WH-003', '', '', 'SKU-3', '3'], // row 4 ok
        ['WH-004', '', '', 'SKU-4', 'x'], // row 5 bad (qty)
      ]);
      expect(result.validCount, 2);
      expect(result.errorCount, 2);
      expect(result.rowErrors.map((e) => e.rowNumber), [3, 5]);
      expect(result.totalDataRows, 4);
    });
  });

  group('whole-file problems', () {
    test('empty file -> fileError, no records', () {
      final result = run([]);
      expect(result.hasFileError, isTrue);
      expect(result.validRecords, isEmpty);
    });

    test('file with only blank rows -> fileError', () {
      final result = run([
        ['', '', ''],
        [null, null],
      ]);
      expect(result.hasFileError, isTrue);
    });

    test('missing a required header column -> fileError naming it', () {
      final result = run([
        ['Warehouse', 'Rack', 'Bin', 'SKU'], // no Qty
        ['WH-001', '', '', 'SKU-1'],
      ]);
      expect(result.hasFileError, isTrue);
      expect(result.fileError, contains('Qty'));
      expect(result.validRecords, isEmpty);
    });
  });

  group('robust column handling', () {
    test('maps columns by header name regardless of order', () {
      final result = run([
        ['Qty', 'SKU', 'Bin', 'Rack', 'Warehouse'],
        ['10', 'SKU-1', 'BIN-001', 'RACK-01', 'WH-001'],
      ]);
      final r = result.validRecords.single;
      expect(r.warehouse, 'WH-001');
      expect(r.sku, 'SKU-1');
      expect(r.qty, 10);
      expect(r.rack, 'RACK-01');
      expect(r.bin, 'BIN-001');
    });

    test('header matching is case-insensitive', () {
      final result = run([
        ['warehouse', 'rack', 'bin', 'sku', 'qty'],
        ['WH-001', '', '', 'SKU-1', '4'],
      ]);
      expect(result.rowErrors, isEmpty);
      expect(result.validRecords.single.warehouse, 'WH-001');
    });

    test('skips fully-blank rows interleaved in the data', () {
      final result = run([
        header,
        ['WH-001', '', '', 'SKU-1', '1'],
        ['', '', '', '', ''], // blank -> skipped, not an error
        ['WH-002', '', '', 'SKU-2', '2'],
      ]);
      expect(result.validCount, 2);
      expect(result.errorCount, 0);
      expect(result.totalDataRows, 2);
    });
  });
}
