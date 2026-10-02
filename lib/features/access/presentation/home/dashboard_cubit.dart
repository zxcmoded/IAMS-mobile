import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/sync/sync_coordinator.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../masterdata/data/hierarchy_repository.dart';
import '../../../masterdata/data/models/company.dart';
import '../controller/selected_location_controller.dart';
import '../controller/selected_location_state.dart';

enum DashboardStatus { loading, loaded, error }

/// State for the offline-first dashboard. Every field is sourced from local
/// SQLite — the dashboard renders with **zero** network calls.
class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.loading,
    this.companyName,
    this.locationName,
    this.locationId,
    this.summary = const InventorySummary(
      totalSkus: 0,
      syncedCount: 0,
      unsyncedCount: 0,
    ),
    this.errorMessage,
  });

  final DashboardStatus status;

  /// Company name from the local hierarchy cache; `null` when the hierarchy has
  /// not synced yet (render a neutral placeholder rather than blocking).
  final String? companyName;

  /// Current location name resolved locally from [locationId]; `null` when the
  /// id is not (yet) in the local cache.
  final String? locationName;

  /// The persisted current-location id, or `null` if somehow unset.
  final String? locationId;

  final InventorySummary summary;
  final String? errorMessage;

  DashboardState copyWith({
    DashboardStatus? status,
    String? companyName,
    String? locationName,
    String? locationId,
    InventorySummary? summary,
    String? errorMessage,
  }) =>
      DashboardState(
        status: status ?? this.status,
        companyName: companyName ?? this.companyName,
        locationName: locationName ?? this.locationName,
        locationId: locationId ?? this.locationId,
        summary: summary ?? this.summary,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  @override
  List<Object?> get props =>
      [status, companyName, locationName, locationId, summary, errorMessage];
}

/// Drives the offline-first dashboard: company (local hierarchy), current
/// location (resolved locally from the persisted id), and the inventory summary
/// (local SQLite counts). Reloads automatically when:
///  * the current-location selection changes (e.g. after "Change"), by
///    subscribing to [SelectedLocationController] the same way
///    [SyncCoordinator] subscribes to auth; and
///  * a background hierarchy/inventory sync pass completes, by subscribing to
///    [SyncCoordinator.onSyncCompleted] — this is what self-corrects the
///    "Selected location" placeholder into the real name shortly after first
///    activation, once the headless sync (fired non-blockingly on
///    authentication — see the doc comment on [SyncCoordinator]) has actually
///    pulled the location into the local hierarchy cache.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required SelectedLocationController selectedLocation,
    required HierarchyRepository hierarchy,
    required InventoryRepository inventory,
    required SyncCoordinator syncCoordinator,
  })  : _selectedLocation = selectedLocation,
        _hierarchy = hierarchy,
        _inventory = inventory,
        _syncCoordinator = syncCoordinator,
        super(const DashboardState()) {
    // Reload when the current-location selection changes (e.g. after "Change").
    _selectedLocationSub = _selectedLocation.stream.listen((_) => load());
    // Reload when a background sync pass finishes, so a location name that
    // wasn't cached yet at first navigation gets picked up without the user
    // having to manually pull-to-refresh.
    _syncSub = _syncCoordinator.onSyncCompleted.listen((_) => load());
  }

  // ignore_for_file: prefer_initializing_formals
  // ^ the fields above are assigned from named params (not `this._x`
  //   initializing formals) purely so DI call sites read as `hierarchy:` etc.

  final HierarchyRepository _hierarchy;
  final InventoryRepository _inventory;
  final SelectedLocationController _selectedLocation;
  final SyncCoordinator _syncCoordinator;

  late final StreamSubscription<SelectedLocationState> _selectedLocationSub;
  late final StreamSubscription<void> _syncSub;

  Future<void> load() async {
    emit(state.copyWith(status: DashboardStatus.loading));
    try {
      final locationId = _selectedLocation.currentLocationId;
      final companies = await _hierarchy.getCompanies();
      final location =
          locationId == null ? null : await _hierarchy.getLocationById(locationId);
      final company = _pickCompany(companies, location?.companyId);
      final summary = await _inventory.loadSummary();

      emit(DashboardState(
        status: DashboardStatus.loaded,
        companyName: company?.name,
        locationName: location?.name,
        locationId: locationId,
        summary: summary,
      ));
    } on ApiException catch (e) {
      // Reads are local-only, so this is unexpected; surface it rather than
      // spinning forever.
      emit(state.copyWith(
        status: DashboardStatus.error,
        errorMessage: e.message,
      ));
    } catch (e, st) {
      developer.log(
        'DashboardCubit.load failed',
        name: 'DashboardCubit',
        error: e,
        stackTrace: st,
        level: 1000, // SEVERE
      );
      emit(state.copyWith(
        status: DashboardStatus.error,
        errorMessage: 'Something went wrong loading your dashboard.',
      ));
    }
  }

  Future<void> refresh() => load();

  /// Picks the company matching the current location's [companyId] (the company
  /// you're operating in); falls back to the first synced company for the common
  /// single-company case. Returns `null` only when nothing has synced yet.
  Company? _pickCompany(List<Company> companies, String? companyId) {
    if (companies.isEmpty) return null;
    if (companyId != null) {
      for (final c in companies) {
        if (c.id == companyId) return c;
      }
    }
    return companies.first;
  }

  @override
  Future<void> close() {
    _selectedLocationSub.cancel();
    _syncSub.cancel();
    return super.close();
  }
}
