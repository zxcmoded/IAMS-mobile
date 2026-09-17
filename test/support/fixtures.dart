import 'package:iams_mobile/core/storage/remembered_activation_key_store.dart';
import 'package:iams_mobile/core/storage/token_store.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';
import 'package:iams_mobile/features/auth/data/models/auth_user.dart';

AuthSession buildSession({
  String accessToken = 'access-1',
  DateTime? accessTokenExpiresAt,
}) {
  return AuthSession(
    accessToken: accessToken,
    tokenType: 'Bearer',
    // Far-future, informational only — there is no refresh cycle.
    accessTokenExpiresAt:
        accessTokenExpiresAt ?? DateTime.utc(2126, 1, 1),
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

/// In-memory [RememberedActivationKeyStore] for tests — no platform channel.
class FakeRememberedActivationKeyStore
    implements RememberedActivationKeyStore {
  String? _key;
  int writes = 0;
  int clears = 0;

  FakeRememberedActivationKeyStore([this._key]);

  /// The currently remembered key, for assertions.
  String? get value => _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String activationKey) async {
    _key = activationKey;
    writes++;
  }

  @override
  Future<void> clear() async {
    _key = null;
    clears++;
  }
}
