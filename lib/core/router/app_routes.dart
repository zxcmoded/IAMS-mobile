/// Route paths and names, centralized so screens and redirects never
/// string-duplicate paths.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const activation = '/activation';
  static const sessionExpired = '/session-expired';

  static const home = '/home';
  static const locationSelect = '/location-select';
  static const accessDenied = '/access/denied';

  // Bottom navigation tabs
  static const audit = '/audit';
  static const settings = '/settings';

  // F3 — Scanning
  static const scanner = '/scan';
  static const manualEntry = '/scan/manual';

  // F4 — Inventory Operations
  static const inventory = '/inventory';
  static const inventoryItem = '/inventory/item'; // + ?id, args via `extra`
  // Offline-first Create Inventory (local-only sessions) + their saved list.
  static const inventoryCreate = '/inventory/create';
  static const inventoryRecords = '/inventory/records';
  static const receive = '/inventory/receive';
  static const transfer = '/inventory/transfer';
  static const adjust = '/inventory/adjust';
  static const stockCount = '/inventory/count';
}
