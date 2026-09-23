import 'selected_location_local_data_source.dart';

/// Read/write access to the persisted current-location selection. Thin over the
/// local data source (mirrors [ScopeRepository]/[HierarchyRepository]); holds no
/// API client, so the selection is purely local state.
class SelectedLocationRepository {
  SelectedLocationRepository(this._local);

  final SelectedLocationLocalDataSource _local;

  Future<String?> readSelectedLocationId() => _local.read();

  Future<void> writeSelectedLocationId(String locationId) =>
      _local.write(locationId);

  Future<void> clearSelectedLocation() => _local.clear();
}
