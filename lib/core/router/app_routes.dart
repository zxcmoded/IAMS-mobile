/// Route paths and names, centralized so screens and redirects never
/// string-duplicate paths.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const twoFactor = '/login/2fa';
  static const sessionExpired = '/session-expired';

  static const companies = '/companies';
  static const connectionScope = '/companies/connection';
  static const crossTenantAccess = '/access';
  static const accessDenied = '/access/denied';
}
