/// Static runtime configuration for the app.
///
/// The API base URL can be overridden at build time with:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
///
/// The default points at the Android emulator's alias for the host loopback
/// (`10.0.2.2`) rather than `localhost`, since `localhost` inside the
/// emulator resolves to the emulator itself, not the host machine running
/// the ASP.NET Core dev server. Override via --dart-define for a physical
/// device, iOS simulator (`localhost` works there), or a remote backend.
/// `/api` is appended by the endpoints themselves, so [apiBaseUrl] is the
/// origin only.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5003',
  );

  /// Timeouts for HTTP calls.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
