import 'package:iams_mobile/features/audit/data/audit_file_service.dart';
import 'package:iams_mobile/features/audit/data/audit_import_parser.dart';
import 'package:iams_mobile/features/audit/data/audit_local_data_source.dart';
import 'package:iams_mobile/features/audit/data/models/audit_record.dart';

/// Builds an [AuditRecord] with sensible defaults for tests.
AuditRecord auditRecord(
  String id, {
  String warehouse = 'WH-001',
  String? rack = 'RACK-01',
  String? bin = 'BIN-001',
  String sku = 'SKU-1',
  double qty = 1,
  DateTime? createdAt,
}) =>
    AuditRecord(
      id: id,
      warehouse: warehouse,
      rack: rack,
      bin: bin,
      sku: sku,
      qty: qty,
      createdAtUtc: createdAt ?? DateTime.utc(2026, 1, 1),
    );

/// In-memory [AuditLocalDataSource] mirroring the SQLite gateway's behaviour:
/// additive insert (id-keyed, replace on conflict), newest-first ordering, count
/// and delete-all. No platform channel / real DB needed — the same approach as
/// the other feature fakes in this repo.
class FakeAuditLocalDataSource implements AuditLocalDataSource {
  final List<AuditRecord> _records = [];

  /// Raw stored records in insertion order, for assertions.
  List<AuditRecord> get stored => List.unmodifiable(_records);

  @override
  Future<void> insertRecords(List<AuditRecord> records) async {
    for (final record in records) {
      _records.removeWhere((r) => r.id == record.id);
      _records.add(record);
    }
  }

  @override
  Future<List<AuditRecord>> getRecords() async {
    final sorted = [..._records]
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return sorted;
  }

  @override
  Future<int> count() async => _records.length;

  @override
  Future<void> deleteAll() async => _records.clear();
}

/// Scriptable [AuditFileService] so cubit flows can be exercised without the
/// real file_picker/path_provider/share_plus plugins.
class FakeAuditFileService implements AuditFileService {
  /// Result returned by the next [pickAndParse] (null = user cancelled).
  AuditImportResult? nextPickResult;

  /// If set, [pickAndParse] throws this instead of returning.
  Object? pickThrows;

  /// If set, export/template calls throw this.
  Object? exportThrows;

  final List<AuditFileFormat> exportedFormats = [];
  final List<List<AuditRecord>> exportedRecords = [];
  final List<AuditFileFormat> templateFormats = [];

  @override
  Future<AuditImportResult?> pickAndParse() async {
    if (pickThrows != null) throw pickThrows!;
    return nextPickResult;
  }

  @override
  Future<String> exportRecords(
      List<AuditRecord> records, AuditFileFormat format) async {
    if (exportThrows != null) throw exportThrows!;
    exportedFormats.add(format);
    exportedRecords.add(List.of(records));
    return 'audit_export.${format.extension}';
  }

  @override
  Future<String> exportTemplate(AuditFileFormat format) async {
    if (exportThrows != null) throw exportThrows!;
    templateFormats.add(format);
    return 'audit_template.${format.extension}';
  }
}
