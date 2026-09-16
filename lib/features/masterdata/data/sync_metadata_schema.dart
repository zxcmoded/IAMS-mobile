/// DDL for the sync bookkeeping tables.
///
/// `sync_metadata` holds one row per hierarchy level (`entity`) with its opaque
/// cursor, status, last-synced time, and a monotonically-increasing
/// `sync_version`. `reachable_company_snapshot` persists the set of company ids
/// the caller could reach as of the last pass — diffed against a fresh full
/// Company pull to detect newly-reachable/newly-unreachable companies (the
/// backend's known timestamp gap) and force a downstream re-pull.
const List<String> syncMetadataSchema = [
  '''
  CREATE TABLE sync_metadata (
    entity TEXT PRIMARY KEY,
    last_cursor TEXT,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    last_synced_at_utc TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE TABLE reachable_company_snapshot (company_id TEXT PRIMARY KEY)',
];
