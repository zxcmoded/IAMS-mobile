import 'models/inventory_record.dart';
import 'inventory_record_local_data_source.dart';

/// **Local-only** access to offline-first Create-Inventory sessions. Constructed
/// with only the local data source — it holds no API client, so saving/reading a
/// record physically cannot reach the network (the same guarantee
/// `InventoryRepository`/`HierarchyRepository` give).
///
/// There is intentionally **no sync path here**: a future Sync feature (not
/// built now) will find `isOffline = true` records and push them. This class
/// never flips `isOffline` to `false`.
class InventoryRecordRepository {
  InventoryRecordRepository(this._local);

  final InventoryRecordLocalDataSource _local;

  /// Persist a newly-created record locally. The caller mints the record with
  /// `isOffline = true`; this method saves it verbatim.
  Future<void> create(InventoryRecord record) => _local.insertRecord(record);

  /// All saved offline records, newest first.
  Future<List<InventoryRecord>> getRecords() => _local.getRecords();

  Future<InventoryRecord?> getRecordById(String id) =>
      _local.getRecordById(id);
}
