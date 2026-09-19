import 'package:connectivity_plus/connectivity_plus.dart';

/// A narrow, mockable connectivity gate. The rest of the app only ever asks a
/// single yes/no question — "is there a usable network right now?" — so this
/// wraps `connectivity_plus` behind [isOnline] rather than leaking its
/// `List<ConnectivityResult>` shape everywhere.
///
/// ⚠️ This reports *interface* connectivity (Wi-Fi/cellular/ethernet present),
/// not reachability of the API. A device on a captive-portal Wi-Fi reads as
/// "online" here; the background sync then fails its first request and is
/// swallowed exactly like any other network error (see [SyncCoordinator]). The
/// point of the check is only to avoid firing sync — and any user-visible
/// delay — when the device is *definitely* offline (airplane mode, no radio).
abstract class ConnectivityChecker {
  Future<bool> isOnline();
}

class ConnectivityPlusChecker implements ConnectivityChecker {
  ConnectivityPlusChecker([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus (v6+) returns a list; "online" is anything other than
      // an empty list or a sole `none`.
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // If the platform channel misbehaves, assume online and let the sync's
      // own network-error handling decide — never let a connectivity probe
      // failure block or crash bootstrap.
      return true;
    }
  }
}
