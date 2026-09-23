import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/audit/data/audit_file_service.dart';
import 'package:iams_mobile/features/audit/data/audit_import_parser.dart';
import 'package:iams_mobile/features/audit/data/audit_repository.dart';
import 'package:iams_mobile/features/audit/presentation/audit_cubit.dart';

import '../../support/audit_fixtures.dart';

void main() {
  late FakeAuditLocalDataSource local;
  late AuditRepository repo;
  late FakeAuditFileService files;
  late AuditCubit cubit;

  setUp(() {
    local = FakeAuditLocalDataSource();
    repo = AuditRepository(local);
    files = FakeAuditFileService();
    cubit = AuditCubit(repo, files);
  });

  tearDown(() => cubit.close());

  test('load surfaces an empty store', () async {
    await cubit.load();
    expect(cubit.state.status, AuditStatus.loaded);
    expect(cubit.state.isEmpty, isTrue);
  });

  test('load reads stored records newest-first', () async {
    await local.insertRecords([
      auditRecord('a', createdAt: DateTime.utc(2026, 1, 1)),
      auditRecord('b', createdAt: DateTime.utc(2026, 1, 3)),
      auditRecord('c', createdAt: DateTime.utc(2026, 1, 2)),
    ]);
    await cubit.load();
    expect(cubit.state.records.map((r) => r.id), ['b', 'c', 'a']);
  });

  group('import', () {
    test('valid file stashes a pending import WITHOUT persisting', () async {
      await cubit.load();
      files.nextPickResult = AuditImportResult(
        validRecords: [auditRecord('1'), auditRecord('2')],
      );

      await cubit.pickAndValidateImport();

      expect(cubit.state.pendingImport, isNotNull);
      expect(cubit.state.pendingImport!.validCount, 2);
      // Nothing written until the user confirms.
      expect(local.stored, isEmpty);
      expect(cubit.state.isBusy, isFalse);
    });

    test('confirm persists valid rows, reloads, and reports the count',
        () async {
      await cubit.load();
      files.nextPickResult = AuditImportResult(
        validRecords: [auditRecord('1'), auditRecord('2')],
      );
      await cubit.pickAndValidateImport();

      await cubit.confirmImport();

      expect(local.stored, hasLength(2));
      expect(cubit.state.records, hasLength(2));
      expect(cubit.state.pendingImport, isNull);
      expect(cubit.state.actionMessage, contains('Imported 2 row'));
    });

    test('confirm message notes skipped invalid rows', () async {
      await cubit.load();
      files.nextPickResult = AuditImportResult(
        validRecords: [auditRecord('1')],
        rowErrors: const [
          AuditRowError(3, [AuditFieldError('Qty', 'must not be negative')]),
        ],
      );
      await cubit.pickAndValidateImport();
      await cubit.confirmImport();

      expect(local.stored, hasLength(1));
      expect(cubit.state.actionMessage, contains('skipped 1 invalid row'));
    });

    test('whole-file error surfaces as actionError, no review opened', () async {
      await cubit.load();
      files.nextPickResult = const AuditImportResult(
        fileError: 'The file is missing required column(s): Qty.',
      );

      await cubit.pickAndValidateImport();

      expect(cubit.state.pendingImport, isNull);
      expect(cubit.state.actionError, contains('Qty'));
      expect(local.stored, isEmpty);
    });

    test('cancelled picker leaves state unchanged', () async {
      await cubit.load();
      files.nextPickResult = null; // user cancelled

      await cubit.pickAndValidateImport();

      expect(cubit.state.pendingImport, isNull);
      expect(cubit.state.actionError, isNull);
      expect(cubit.state.isBusy, isFalse);
    });

    test('decode failure surfaces the exception message', () async {
      await cubit.load();
      files.pickThrows = const AuditFileException('The .xlsx file is corrupt.');

      await cubit.pickAndValidateImport();

      expect(cubit.state.actionError, 'The .xlsx file is corrupt.');
    });

    test('cancelImport clears the pending review without saving', () async {
      await cubit.load();
      files.nextPickResult =
          AuditImportResult(validRecords: [auditRecord('1')]);
      await cubit.pickAndValidateImport();

      cubit.cancelImport();

      expect(cubit.state.pendingImport, isNull);
      expect(local.stored, isEmpty);
    });
  });

  group('export', () {
    test('is blocked (with a message) when there are no records', () async {
      await cubit.load();
      await cubit.exportRecords(AuditFileFormat.csv);

      expect(cubit.state.actionError, contains('no audit records'));
      expect(files.exportedFormats, isEmpty);
    });

    test('exports stored records in the chosen format', () async {
      await local.insertRecords([auditRecord('1')]);
      await cubit.load();

      await cubit.exportRecords(AuditFileFormat.xlsx);

      expect(files.exportedFormats, [AuditFileFormat.xlsx]);
      expect(files.exportedRecords.single, hasLength(1));
      expect(cubit.state.actionMessage, contains('Exported 1 row'));
    });

    test('export failure surfaces an error', () async {
      await local.insertRecords([auditRecord('1')]);
      await cubit.load();
      files.exportThrows = Exception('disk full');

      await cubit.exportRecords(AuditFileFormat.csv);

      expect(cubit.state.actionError, contains('Could not export'));
    });
  });

  group('template', () {
    test('delegates to the file service in the chosen format', () async {
      await cubit.load();
      await cubit.downloadTemplate(AuditFileFormat.csv);

      expect(files.templateFormats, [AuditFileFormat.csv]);
      expect(cubit.state.actionMessage, contains('template'));
    });
  });

  test('clearAll empties the store', () async {
    await local.insertRecords([auditRecord('1'), auditRecord('2')]);
    await cubit.load();
    expect(cubit.state.records, hasLength(2));

    await cubit.clearAll();

    expect(local.stored, isEmpty);
    expect(cubit.state.records, isEmpty);
    expect(cubit.state.actionMessage, contains('Cleared'));
  });
}
