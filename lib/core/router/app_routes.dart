/// Route paths and names, centralized so screens and redirects never
/// string-duplicate paths.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const activation = '/activation';
  static const sessionExpired = '/session-expired';

  static const sync = '/sync';

  static const companies = '/companies';
  static const connectionScope = '/companies/connection';
  static const crossTenantAccess = '/access';
  static const accessDenied = '/access/denied';

  // F3 — Scanning
  static const scanner = '/scan';
  static const manualEntry = '/scan/manual';

  // F4 — Inventory Operations
  static const inventory = '/inventory';
  static const inventoryItem = '/inventory/item'; // + ?id, args via `extra`
  static const receive = '/inventory/receive';
  static const transfer = '/inventory/transfer';
  static const adjust = '/inventory/adjust';
  static const stockCount = '/inventory/count';
}
