import 'package:flutter_test/flutter_test.dart';
import 'package:iams_mobile/core/network/api_exception.dart';
import 'package:iams_mobile/core/network/problem_details.dart';

void main() {
  group('ProblemDetailsParser', () {
    test('parses a ProblemDetails body with a machine-readable code', () {
      final ex = ProblemDetailsParser.parse(
        data: {
          'type': 'https://tools.ietf.org/html/rfc9110',
          'title': 'Invalid username or password.',
          'status': 401,
          'code': 'invalid_credentials',
        },
        statusCode: 401,
      );

      expect(ex.code, ApiErrorCode.invalidCredentials);
      expect(ex.statusCode, 401);
      expect(ex.message, 'Invalid username or password.');
      expect(ex.errors, isEmpty);
    });

    test('parses 400 validation_failed with a field errors map', () {
      final ex = ProblemDetailsParser.parse(
        data: {
          'title': 'One or more validation errors occurred.',
          'status': 400,
          'code': 'validation_failed',
          'errors': {
            'Username': ["'Username' must not be empty."],
          },
        },
        statusCode: 400,
      );

      expect(ex.code, ApiErrorCode.validationFailed);
      expect(ex.errors['Username'], ["'Username' must not be empty."]);
    });

    test('prefers detail over title for the message when present', () {
      final ex = ProblemDetailsParser.parse(
        data: {
          'title': 'Short',
          'detail': 'A longer human explanation.',
          'code': 'session_expired',
        },
        statusCode: 401,
      );
      expect(ex.message, 'A longer human explanation.');
      expect(ex.isSessionExpired, isTrue);
    });

    test('captures the informational traceId when present', () {
      final ex = ProblemDetailsParser.parse(
        data: {
          'title': 'No active company.',
          'status': 403,
          'code': 'no_active_company',
          'traceId': '00-abc123-def456-01',
        },
        statusCode: 403,
      );
      expect(ex.code, 'no_active_company');
      expect(ex.traceId, '00-abc123-def456-01');
    });

    test('falls back to unknown code when body is not ProblemDetails', () {
      final ex = ProblemDetailsParser.parse(data: 'oops', statusCode: 500);
      expect(ex.code, ApiErrorCode.unknown);
      expect(ex.statusCode, 500);
    });

    test('bodyless 429 (IP rate limit) → rate_limited without crashing', () {
      final exNull = ProblemDetailsParser.parse(data: null, statusCode: 429);
      expect(exNull.code, ApiErrorCode.rateLimited);
      expect(exNull.message, contains('Too many requests'));

      final exEmpty = ProblemDetailsParser.parse(data: '', statusCode: 429);
      expect(exEmpty.code, ApiErrorCode.rateLimited);
    });
  });
}
