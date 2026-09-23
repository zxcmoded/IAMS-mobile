import 'package:equatable/equatable.dart';

enum SelectedLocationLoadStatus {
  /// Startup: the persisted selection has not been read yet.
  unknown,

  /// The persisted selection has been read (present or absent).
  ready,
}

/// App-wide state for the persisted current-location selection. The router
/// redirects off [hasSelection] the same way it redirects off `AuthStatus`.
class SelectedLocationState extends Equatable {
  const SelectedLocationState({required this.status, this.locationId});

  const SelectedLocationState.unknown()
      : this(status: SelectedLocationLoadStatus.unknown);

  const SelectedLocationState.ready(String? locationId)
      : this(status: SelectedLocationLoadStatus.ready, locationId: locationId);

  final SelectedLocationLoadStatus status;
  final String? locationId;

  /// Whether a current location has been chosen and persisted. `false` before
  /// the first selection (the one-time gate condition) and while still loading.
  bool get hasSelection => locationId != null;

  @override
  List<Object?> get props => [status, locationId];
}
