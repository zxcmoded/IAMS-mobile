import 'hierarchy_local_data_source.dart';
import 'models/bin.dart';
import 'models/company.dart';
import 'models/location.dart';
import 'models/rack.dart';
import 'models/warehouse.dart';

/// Read-only access to the synced hierarchy for the UI. Constructed with **only**
/// the local data source — it holds no [HierarchyApi], so a screen reading
/// through this repository physically cannot reach the network. All syncing
/// (the only thing that touches the API) lives in `HierarchySyncService`.
class HierarchyRepository {
  HierarchyRepository(this._local);

  final HierarchyLocalDataSource _local;

  Future<List<Company>> getCompanies() => _local.getCompanies();

  Future<List<Location>> getLocations(String companyId) =>
      _local.getLocations(companyId: companyId);

  Future<Location?> getLocationById(String id) =>
      _local.getLocationById(id);

  Future<List<Warehouse>> getWarehouses(String locationId) =>
      _local.getWarehouses(locationId: locationId);

  Future<List<Rack>> getRacks(String warehouseId) =>
      _local.getRacks(warehouseId: warehouseId);

  Future<List<Bin>> getBins(String rackId) => _local.getBins(rackId: rackId);
}
