import 'package:iams_mobile/core/storage/token_store.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';

AuthSession buildSession({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  DateTime? refreshExpiry,
}) {
  return AuthSession(
    accessToken: accessToken,
    tokenType: 'Bearer',
    accessTokenExpiresAt:
        DateTime.now().toUtc().add(const Duration(minutes: 15)),
    refreshToken: refreshToken,
    refreshTokenExpiresAt:
        refreshExpiry ?? DateTime.now().toUtc().add(const Duration(days: 30)),
    user: const AuthUser(id: 'u1', username: 'alice', displayName: 'Alice'),
  );
}

/// In-memory [TokenStore] for tests — no platform channel needed.
class FakeTokenStore implements TokenStore {
  AuthSession? _session;
  int writes = 0;
  int clears = 0;

  FakeTokenStore([this._session]);

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async {
    _session = session;
    writes++;
  }

  @override
  Future<void> clear() async {
    _session = null;
    clears++;
  }
}
