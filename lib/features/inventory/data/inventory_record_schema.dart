/// DDL for the **offline-first Create-Inventory** feature — a locally-created
/// inventory/cycle-count *session* (header + SKU lines) that is saved entirely
/// on-device with `is_offline = 1` and has **no** sync path yet. Added in
/// database schema **v5** (see [AppDatabase]); both the `onCreate` batch and the
/// v4→v5 `onUpgrade` path run these statements.
///
/// This is a **distinct** entity from the synced `inventory_item` master and the
/// `outbox_mutation` stock-count flow — it never reuses or mutates those tables.
///
/// - `inventory_record` — one row per saved session. `warehouse_id` is required;
///   `rack_id`/`bin_id` are nullable (both optional in the flow). The
///   `*_name` columns are denormalized copies of the master-data labels captured
///   at save time so the offline records list renders without any hierarchy
///   lookup. `is_offline` is always `1` on insert and is never flipped to `0` by
///   the app (a future Sync feature owns that transition).
/// - `inventory_record_line` — one row per SKU line, keyed by
///   `(record_id, inventory_item_id)` so a repeated scan of the same SKU
///   accumulates onto one line instead of inserting a duplicate. `sku`/
///   `item_name` are denormalized for offline display. Deleting a record cascades
///   to its lines (`ON DELETE CASCADE`, with `PRAGMA foreign_keys = ON`).
const List<String> inventoryRecordSchema = [
  '''
  CREATE TABLE inventory_record (
    id TEXT PRIMARY KEY,
    warehouse_id TEXT NOT NULL,
    warehouse_name TEXT NOT NULL,
    rack_id TEXT,
    rack_name TEXT,
    bin_id TEXT,
    bin_name TEXT,
    is_offline INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_inventory_record_created ON inventory_record(created_at_utc)',
  '''
  CREATE TABLE inventory_record_line (
    record_id TEXT NOT NULL,
    inventory_item_id TEXT NOT NULL,
    sku TEXT NOT NULL,
    item_name TEXT NOT NULL,
    quantity REAL NOT NULL,
    PRIMARY KEY (record_id, inventory_item_id),
    FOREIGN KEY (record_id) REFERENCES inventory_record(id) ON DELETE CASCADE
  )
  ''',
];
