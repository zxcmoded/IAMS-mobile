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
