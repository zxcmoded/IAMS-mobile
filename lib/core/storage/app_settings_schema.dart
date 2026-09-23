/// DDL for the app-wide **local settings** store — a small key/value table for
/// non-sensitive, device-local UI state that must survive restarts but is not a
/// secret. Added in database schema **v4** (see [AppDatabase]); both the
/// `onCreate` batch and the v3→v4 `onUpgrade` path run these statements.
///
/// - `app_setting` — one row per setting. `key` is the stable setting name
///   (e.g. `selected_location_id`), `value` its text payload. Deliberately a
///   generic key/value table rather than a single-purpose one so future local
///   preferences reuse it without another migration.
///
/// This is **not** for secrets: the auth token lives in `flutter_secure_storage`
/// (see [SecureTokenStore]). The current-location selection persisted here is
/// plain UI state, not a credential.
const List<String> appSettingsSchema = [
  '''
  CREATE TABLE app_setting (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
];
