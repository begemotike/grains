# CSV export

`CSVExporter` in `GrainsReports` (pure: entries + week → bytes) and `ExportService` in the app (watches the store, debounces, writes atomically).

## Files

`<folder>/Grains-YYYY-Www.csv`, one per ISO week (`Week.isoIdentifier`). Default folder `~/Documents/Grains`, changeable in Settings. UTF-8, no BOM, `\n` line endings, RFC 4180 quoting (fields containing `,` `"` or newlines are quoted, `"` doubled).

## Schema (binding; version 1)

| Column | Content |
|---|---|
| `id` | Entry UUID |
| `week` | `2026-W44` |
| `started_at` | RFC 3339 with the local offset at that instant, e.g. `2026-10-27T09:14:03-08:00` |
| `stopped_at` | Same, or empty while running |
| `started_local_date` | `2026-10-27` |
| `started_local_time` | `09:14:03` |
| `stopped_local_date`, `stopped_local_time` | same, or empty |
| `duration_seconds` | Integer seconds of this entry **within this week** (a session crossing the week boundary appears in both files with the respective portions; `whole_duration_seconds` has the full value) |
| `whole_duration_seconds` | Integer, full session as of export time |
| `hours` | `duration_seconds / 3600` with 2 decimals |
| `raw_text` | Exactly as typed |
| `client_text` | Parsed client, may be empty |
| `note` | Parsed note, may be empty |
| `client_id` | Normalized client UUID or empty |
| `running` | `true`/`false` |
| `recovered` | `true` when the stop was set by crash recovery and not reconciled |
| `created_at`, `updated_at` | RFC 3339 with offset |

Header row always present. Rows ordered by `started_at`. Deleted entries are excluded. The time zone used for local columns is the one in effect at export time (`WeekSpec.calendar.timeZone`); the RFC 3339 columns are unambiguous regardless.

A first comment line is **not** used (breaks many importers). The schema version is in the filename convention only; a change in columns bumps to `Grains-YYYY-Www.v2.csv` so importers never silently break.

## When files are written (D17)

- Any store change → the week(s) containing the changed entry's start (and stop, if different) are scheduled; debounce 5 s; one write per scheduled week.
- Week rollover → the finished week is written once more (final) and the new week file is created on its first entry.
- Settings → "Export all weeks now" regenerates every week from `earliestStart()` to now.
- Writes are atomic: write to `<file>.tmp-<uuid>` in the same directory, `fsync`, then `rename(2)` over the target.

## Determinism

Same database + same time zone + same export time (for running entries) → byte-identical file. Tests compare against fixtures.
