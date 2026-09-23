/// DDL for the fully-offline **Audit** feature — a flat, self-contained local
/// table of imported audit rows. Added in database schema **v6** (see
/// [AppDatabase]); both the `onCreate` batch and the v5→v6 `onUpgrade` path run
/// these statements.
///
/// This table is deliberately **standalone**: unlike `inventory_record`, it does
/// NOT reference the master-data hierarchy (`warehouse_id`/`rack_id`/`bin_id`) or
/// the `inventory_item` master. Its columns are the raw spec fields, because the
/// data originates from an arbitrary user-supplied CSV/XLSX file that may contain
/// warehouse/SKU codes the local master data has never seen. The whole feature
/// makes **no** API/network calls — import, validation, and export are 100% local.
///
/// - `audit_record` — one row per imported audit line. `warehouse` and `sku` are
///   required (validated before insert); `rack`/`bin` are nullable (optional in
///   the spec). `qty` is a non-negative number stored as REAL. `id` is a
///   client-minted UUID; `created_at_utc` records when the row was imported so
///   the list can render newest-first.
const List<String> auditSchema = [
  '''
  CREATE TABLE audit_record (
    id TEXT PRIMARY KEY,
    warehouse TEXT NOT NULL,
    rack TEXT,
    bin TEXT,
    sku TEXT NOT NULL,
    qty REAL NOT NULL,
    created_at_utc TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_audit_record_created ON audit_record(created_at_utc)',
];
