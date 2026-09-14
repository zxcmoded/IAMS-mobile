import '../../../core/storage/device_id_provider.dart';
import 'auth_api.dart';
import 'models/auth_session.dart';

/// Orchestrates the auth API with the per-install device id. Token persistence
/// is owned by [AuthController] (single writer), so this layer stays stateless.
class AuthRepository {
  AuthRepository(this._api, this._deviceIdProvider);

  final AuthApi _api;
  final DeviceIdProvider _deviceIdProvider;

  /// Activates the account with the given key on this device, returning a
  /// fresh session. `deviceId` is required by the contract (unlike
  /// [refresh]'s optional one) — it's the single enforcement point for
  /// device binding.
  Future<AuthSession> activate(String activationKey) async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    return _api.activate(activationKey: activationKey, deviceId: deviceId);
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    return _api.refresh(refreshToken: refreshToken, deviceId: deviceId);
  }

  Future<void> logout({
    required String accessTokenHeader,
    required String refreshToken,
  }) =>
      _api.logout(
        accessTokenHeader: accessTokenHeader,
        refreshToken: refreshToken,
      );
}
