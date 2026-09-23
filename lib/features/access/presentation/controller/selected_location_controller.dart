import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/selected_location_repository.dart';
import 'selected_location_state.dart';

/// The single source of truth for the persisted current-location selection and
/// its lifecycle — the location the user chose to operate within after
/// activation.
///
/// Wired into the router the same way [AuthController] is: its [stream] feeds
/// `GoRouter.refreshListenable`, and the redirect reads [state] synchronously.
/// An authenticated user with no selection ([SelectedLocationState.hasSelection]
/// `== false`) is routed to the one-time location-select gate; once [select] is
/// called the redirect lets them through to Home and every subsequent launch
/// (which restores the selection via [load]) skips the gate.
class SelectedLocationController extends Cubit<SelectedLocationState> {
  SelectedLocationController(this._repository)
      : super(const SelectedLocationState.unknown());

  final SelectedLocationRepository _repository;

  String? get currentLocationId => state.locationId;

  /// Called once at startup (before the first frame, alongside
  /// `AuthController.bootstrap`) to restore any persisted selection.
  Future<void> load() async {
    final id = await _repository.readSelectedLocationId();
    emit(SelectedLocationState.ready(id));
  }

  /// Persist and activate the user's chosen current location. Emitting the new
  /// state drives the router (via `refreshListenable`) to permit Home.
  Future<void> select(String locationId) async {
    await _repository.writeSelectedLocationId(locationId);
    emit(SelectedLocationState.ready(locationId));
  }

  /// Forget the selection (used on the "forget this device" hand-off) so the
  /// next activation re-shows the one-time gate.
  Future<void> clear() async {
    await _repository.clearSelectedLocation();
    emit(const SelectedLocationState.ready(null));
  }
}
