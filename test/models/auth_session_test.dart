import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/features/auth/data/models/auth_session.dart';

void main() {
  group('AuthSession', () {
    final json = {
      'accessToken': 'jwt-abc',
      'tokenType': 'Bearer',
      'accessTokenExpiresAt': '2026-09-09T12:49:56+00:00',
      'refreshToken': 'refresh-xyz',
      'refreshTokenExpiresAt': '2026-10-09T12:34:56+00:00',
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

    test('isAccessTokenExpired accounts for a 30s skew', () {
      final session = AuthSession.fromJson(json);
      final justBeforeExpiry =
          DateTime.parse('2026-09-09T12:49:40+00:00'); // 16s before
      expect(session.isAccessTokenExpired(now: justBeforeExpiry), isTrue);

      final wellBefore = DateTime.parse('2026-09-09T12:00:00+00:00');
      expect(session.isAccessTokenExpired(now: wellBefore), isFalse);
    });
  });
}
