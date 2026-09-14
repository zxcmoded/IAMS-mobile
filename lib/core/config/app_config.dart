/// Static runtime configuration for the app.
///
/// The API base URL can be overridden at build time with:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
///
/// The default points at the conventional local ASP.NET Core dev host so the
/// mobile client can talk to the backend teammate's service without extra
/// wiring once it is running. `/api` is appended by the endpoints themselves,
/// so [apiBaseUrl] is the origin only.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://localhost:5001',
  );

  /// Timeouts for HTTP calls.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
