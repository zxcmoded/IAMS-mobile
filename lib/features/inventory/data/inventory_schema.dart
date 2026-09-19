/// DDL for the F4 offline-first inventory tables — the local-commit + outbox
/// queue mechanism. Added in database schema **v2** (see [AppDatabase]); both
/// the `onCreate` batch and the v1→v2 `onUpgrade` path run these statements.
///
/// - `outbox_mutation` — one row per queued mutation. `idempotency_key` is the
///   stable client-generated id (also the PK, so a re-commit of the same
///   logical mutation can't create a duplicate row). `payload`/`response_json`
///   are JSON text. Ordering for in-order replay is by `created_at_utc` then
///   `rowid` (insertion order tiebreak).
/// - `stock_version_cache` — last-observed authoritative on-hand + version per
///   (item, bin); the offline conflict basis and optimistic-display source.
const List<String> inventorySchema = [
  '''
  CREATE TABLE outbox_mutation (
    idempotency_key TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    inventory_item_id TEXT NOT NULL,
    payload TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT,
    last_error_code TEXT,
    last_error_message TEXT,
    response_json TEXT
  )
  ''',
  'CREATE INDEX idx_outbox_status ON outbox_mutation(status)',
  'CREATE INDEX idx_outbox_item ON outbox_mutation(inventory_item_id)',
  '''
  CREATE TABLE stock_version_cache (
    inventory_item_id TEXT NOT NULL,
    bin_id TEXT NOT NULL,
    quantity_on_hand REAL NOT NULL,
    version INTEGER NOT NULL,
    updated_at_utc TEXT NOT NULL,
    PRIMARY KEY (inventory_item_id, bin_id)
  )
  ''',
];

/// DDL for the F4 **offline-first inventory read cache** — the master-data half
/// of the inventory store, added in database schema **v3** (see [AppDatabase]).
///
/// - `inventory_item` — the SKU master mirrored from `GET /inventory/sync/items`
///   (`InventoryItemSyncDto`). One row per item; `is_active = 0` marks a
///   soft-deleted item that is upserted-and-kept (never hard-deleted on
///   absence). It carries no foreign key to `company` on purpose: the inventory
///   sync and the hierarchy sync run concurrently and independently, so an
///   inventory row must be insertable before its company has been pulled. `sku`
///   is indexed because the list view sorts by it (matching the server's
///   `ORDER BY Sku, Id`).
///   Per-bin on-hand is **not** stored here — it lives in `stock_version_cache`
///   (already the reconcile target for the outbox mutation flow), which the
///   list/detail read path joins against to compute aggregate on-hand.
/// - `inventory_reachable_snapshot` — the set of company ids reachable as of the
///   inventory sync's last pass. Diffed against a fresh full Company pull to
///   detect a newly-reachable company (the backend's known `SyncCursorUtc` gap:
///   enabling a connection does not bump that company's inventory rows' cursor)
///   and force a full re-pull of both inventory feeds. This is inventory's own
///   snapshot, kept separate from the hierarchy sync's `reachable_company_snapshot`
///   so the two syncs never race on a shared diff basis.
const List<String> inventoryMasterSchema = [
  '''
  CREATE TABLE inventory_item (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    sku TEXT NOT NULL,
    barcode TEXT,
    name TEXT NOT NULL,
    description TEXT,
    unit_of_measure TEXT,
    category TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT
  )
  ''',
  'CREATE INDEX idx_inventory_item_sku ON inventory_item(sku COLLATE NOCASE)',
  'CREATE INDEX idx_inventory_item_company_id ON inventory_item(company_id)',
  'CREATE TABLE inventory_reachable_snapshot (company_id TEXT PRIMARY KEY)',
];
