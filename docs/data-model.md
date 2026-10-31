# Data model and storage

## Schema (SQLite, WAL, `user_version` = 1)

```sql
CREATE TABLE entries (
  id               TEXT PRIMARY KEY,            -- UUID string, uppercase
  raw_text         TEXT NOT NULL,               -- exactly as typed, immutable
  client_text      TEXT,                        -- parsed provisional client label
  note             TEXT,                        -- parsed note
  client_id        TEXT,                        -- optional normalized client UUID (future)
  started_at       REAL NOT NULL,               -- Unix seconds, UTC
  stopped_at       REAL,                        -- NULL while running
  duration_seconds REAL,                        -- derived; recomputed on every write (D6)
  created_at       REAL NOT NULL,
  updated_at       REAL NOT NULL,
  deleted_at       REAL,                        -- soft delete
  metadata         TEXT NOT NULL DEFAULT '{}'   -- JSON of EntryMetadata
);
CREATE UNIQUE INDEX entries_one_running ON entries((stopped_at IS NULL)) WHERE stopped_at IS NULL AND deleted_at IS NULL;
CREATE INDEX entries_started_at ON entries(started_at);
CREATE INDEX entries_client_text ON entries(client_text COLLATE NOCASE);

CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- keys: 'heartbeat_entry_id', 'heartbeat_at' (Unix seconds), 'clean_shutdown' ('1' when the app quit normally)
```

The partial unique index on the expression `(stopped_at IS NULL)` is the database-level guarantee (indexing the bare column would not work: SQLite treats every NULL as distinct in a UNIQUE index, see D23) of "one running timer". Starting a new entry is therefore always `UPDATE running SET stopped_at = ?` then `INSERT`, inside one transaction.

## Mapping to `Entry`

See `Sources/GrainsCore/Entry.swift`. Dates are stored as Unix seconds (REAL) and read back as `Date(timeIntervalSince1970:)`. `metadata` is `JSONEncoder`/`JSONDecoder` of `EntryMetadata` with sorted keys for deterministic diffs.

## Migrations

`SQLiteEntryStore.open(at:)` runs `PRAGMA user_version`; migrations are an array of SQL scripts applied in a transaction from the current version upward. v1 ships version 1. Never edit a shipped migration; add a new one.

## Read-only opening

`SQLiteEntryStore.openReadOnly(at:)` uses `SQLITE_OPEN_READONLY`. WAL mode lets readers proceed while the app writes. The MCP server uses this and refuses to construct an `EntryWriting`.

## Path resolution

`GrainsPaths.databaseURL` → `$GRAINS_DB_PATH` if set, else `~/Library/Application Support/Grains/grains.sqlite` (directory created on demand). `GrainsPaths.defaultExportDirectory` → `~/Documents/Grains`.

## Soft delete

`deleted_at` set; rows stay. All `EntryReading` queries filter `deleted_at IS NULL`. Restoring is clearing the column (History window, v1 Undo).
