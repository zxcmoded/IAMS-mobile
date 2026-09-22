/// DDL for the master-data hierarchy tables (Company → Location → Warehouse →
/// Rack → Bin). Each level stores every denormalized ancestor id present on the
/// backend DTO (`company_id` down to the leaf), mirrored from the server for
/// local joins/filtering. `is_active` is `0`/`1`; timestamps are ISO-8601
/// strings; `updated_at_utc`/`region` are nullable.
///
/// Executed once by [AppDatabase]'s `onCreate`. Foreign keys are enforced
/// (`PRAGMA foreign_keys = ON` in `onConfigure`), so parents must be upserted
/// before children — which the sync order (Company→Bin) guarantees.
const List<String> hierarchySchema = [
  '''
  CREATE TABLE company (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  '''
  CREATE TABLE location (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES company(id),
    name TEXT NOT NULL,
    region TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_location_company_id ON location(company_id)',
  '''
  CREATE TABLE warehouse (
    id TEXT PRIMARY KEY,
    location_id TEXT NOT NULL REFERENCES location(id),
    company_id TEXT NOT NULL,
    name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_warehouse_location_id ON warehouse(location_id)',
  'CREATE INDEX idx_warehouse_company_id ON warehouse(company_id)',
  '''
  CREATE TABLE rack (
    id TEXT PRIMARY KEY,
    warehouse_id TEXT NOT NULL REFERENCES warehouse(id),
    location_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_rack_warehouse_id ON rack(warehouse_id)',
  'CREATE INDEX idx_rack_company_id ON rack(company_id)',
  '''
  CREATE TABLE bin (
    id TEXT PRIMARY KEY,
    rack_id TEXT NOT NULL REFERENCES rack(id),
    warehouse_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_bin_rack_id ON bin(rack_id)',
  'CREATE INDEX idx_bin_company_id ON bin(company_id)',
];
