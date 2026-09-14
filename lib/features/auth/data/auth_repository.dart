import '../../../core/storage/device_id_provider.dart';
import 'auth_api.dart';
import 'models/auth_challenge.dart';
import 'models/auth_session.dart';

/// Orchestrates the auth API with the per-install device id. Token persistence
/// is owned by [AuthController] (single writer), so this layer stays stateless.
class AuthRepository {
  AuthRepository(this._api, this._deviceIdProvider);

  final AuthApi _api;
  final DeviceIdProvider _deviceIdProvider;

  Future<AuthChallenge> login({
    required String username,
    required String password,
  }) async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    return _api.login(
      username: username,
      password: password,
      deviceId: deviceId,
    );
  }

  Future<AuthSession> verifyTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    final deviceId = await _deviceIdProvider.getDeviceId();
    return _api.verifyTwoFactor(
      challengeToken: challengeToken,
      code: code,
      deviceId: deviceId,
    );
  }

  Future<AuthChallenge> resendTwoFactor(String challengeToken) =>
      _api.resendTwoFactor(challengeToken: challengeToken);

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
