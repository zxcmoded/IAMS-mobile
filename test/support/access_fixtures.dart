import 'package:iams_mobile/features/access/data/models/scope.dart';
import 'package:iams_mobile/features/access/data/selected_location_local_data_source.dart';
import 'package:iams_mobile/features/access/data/selected_location_repository.dart';
import 'package:iams_mobile/features/access/presentation/controller/selected_location_controller.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';
import 'package:iams_mobile/features/auth/data/models/role.dart';

/// A [LocationRef] for the location-select list.
LocationRef locRef(String id, {String? name}) =>
    LocationRef(id: id, name: name ?? 'Location $id');

/// A [Scope] fixture (the `GET /me/scope` payload the location-select gate
/// consumes). Defaults to a location-restricted `User` with the given
/// [locations] assigned.
Scope scope({
  List<LocationRef> locations = const [],
  Role role = Role.user,
  bool unrestrictedCompanyAccess = false,
  String companyId = 'co1',
  String companyName = 'Acme',
}) =>
    Scope(
      user: const AuthUser(id: 'u1', username: 'alice', displayName: 'Alice'),
      role: role,
      company: CompanyRef(id: companyId, name: companyName),
      assignedLocations: locations,
      unrestrictedCompanyAccess: unrestrictedCompanyAccess,
      systemWideAccess: false,
    );

/// In-memory [SelectedLocationLocalDataSource] — no platform channel / real DB,
/// same approach as the other `Fake…LocalDataSource`s.
class FakeSelectedLocationLocalDataSource
    implements SelectedLocationLocalDataSource {
  FakeSelectedLocationLocalDataSource([this._id]);

  String? _id;

  /// The currently persisted id, for assertions.
  String? get value => _id;

  @override
  Future<String?> read() async => _id;

  @override
  Future<void> write(String locationId) async => _id = locationId;

  @override
  Future<void> clear() async => _id = null;
}

/// A [SelectedLocationController] backed by an in-memory store, optionally
/// pre-seeded with [initial]. Not yet `load()`ed — call `load()` to move it to
/// the ready state when the test needs it.
SelectedLocationController buildSelectedLocationController({String? initial}) =>
    SelectedLocationController(
      SelectedLocationRepository(
        FakeSelectedLocationLocalDataSource(initial),
      ),
    );
