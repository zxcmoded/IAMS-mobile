import 'models/audit_record.dart';
import 'audit_local_data_source.dart';

/// **Local-only** access to Audit rows. Constructed with only the local data
/// source — it holds no API client, so importing/reading/exporting audit data
/// physically cannot reach the network (the same guarantee
/// `InventoryRepository`/`InventoryRecordRepository` give). This satisfies the
/// spec's hard requirement that the Audit feature make no API calls at all.
class AuditRepository {
  AuditRepository(this._local);

  final AuditLocalDataSource _local;

  /// Persist a batch of validated audit rows locally (additive).
  Future<void> importRecords(List<AuditRecord> records) =>
      _local.insertRecords(records);

  /// All stored audit rows, newest first.
  Future<List<AuditRecord>> getRecords() => _local.getRecords();

  Future<int> count() => _local.count();

  /// Remove all stored audit rows.
  Future<void> clear() => _local.deleteAll();
}
