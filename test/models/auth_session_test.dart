import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';

void main() {
  group('AuthSession', () {
    final json = {
      'accessToken': 'jwt-abc',
      'tokenType': 'Bearer',
      'accessTokenExpiresAt': '2126-01-01T00:00:00+00:00',
      'user': {'id': 'u1', 'username': 'alice', 'displayName': 'Alice'},
    };

    test('round-trips through fromJson/toJson', () {
      final session = AuthSession.fromJson(json);
      expect(session.accessToken, 'jwt-abc');
      expect(session.user.username, 'alice');
      expect(session.authorizationHeader, 'Bearer jwt-abc');

      final restored = AuthSession.fromJson(session.toJson());
      expect(restored, session);
    });

    test('ignores refresh fields if a legacy payload still carries them', () {
      // The backend no longer returns refresh tokens; a stale/legacy body must
      // still deserialize without error and simply drop the extra fields.
      final legacy = {
        ...json,
        'refreshToken': 'refresh-xyz',
        'refreshTokenExpiresAt': '2126-02-01T00:00:00+00:00',
      };
      final session = AuthSession.fromJson(legacy);
      expect(session.accessToken, 'jwt-abc');
      expect(session.toJson().containsKey('refreshToken'), isFalse);
    });
  });
}
