#!/bin/bash
# Seeds a development Grains database with realistic entries (current + previous week) for screenshots.
# Plain sqlite3 so it does not depend on the Swift store; schema mirrors docs/data-model.md (user_version 1).
#
#   scripts/dev-db.sh                         # writes /tmp/grains-dev.sqlite (replacing it)
#   GRAINS_DB_PATH=~/x.sqlite scripts/dev-db.sh
#   GRAINS_DB_PATH=/tmp/grains-dev.sqlite open -a Grains   # point the app at it
set -euo pipefail
DB="${GRAINS_DB_PATH:-/tmp/grains-dev.sqlite}"
command -v sqlite3 >/dev/null || { echo "sqlite3 not found"; exit 1; }
rm -f "$DB" "$DB-wal" "$DB-shm"
mkdir -p "$(dirname "$DB")"

# Monday 00:00 local time of the current week, as Unix seconds.
DOW=$(date +%u)                                   # 1 = Monday
MONDAY=$(date -v-"$((DOW - 1))"d -v0H -v0M -v0S +%s)
NOW=$(date +%s)

# day offset from this Monday (negative = previous week), start "HH:MM", minutes, raw text
ENTRIES=(
  "-7|08:30|95|Global Credit Union - Jamf certificate troubleshooting"
  "-7|10:15|45|Administrative work"
  "-6|09:00|150|Denali - iPad enrollment issue"
  "-5|13:00|120|Spruce - Policy engine"
  "-4|08:45|75|Global Credit Union - Conditional access review"
  "-3|14:30|60|Denali - Shared iPad cart setup"
  "-3|16:00|30|Administrative work"
  "0|08:30|110|Spruce - Policy engine"
  "0|11:00|50|Global Credit Union - Jamf certificate troubleshooting"
  "1|09:15|90|Denali - iPad enrollment issue"
  "1|13:30|40|Administrative work"
  "2|10:00|130|Spruce - Onboarding flow copy"
)

sql_quote() { printf "'%s'" "${1//\'/\'\'}"; }
uuid() { uuidgen | tr '[:lower:]' '[:upper:]'; }

{
  cat <<'SQL'
PRAGMA journal_mode = WAL;
BEGIN;
CREATE TABLE entries (
  id               TEXT PRIMARY KEY,
  raw_text         TEXT NOT NULL,
  client_text      TEXT,
  note             TEXT,
  client_id        TEXT,
  started_at       REAL NOT NULL,
  stopped_at       REAL,
  duration_seconds REAL,
  created_at       REAL NOT NULL,
  updated_at       REAL NOT NULL,
  deleted_at       REAL,
  metadata         TEXT NOT NULL DEFAULT '{}'
);
CREATE UNIQUE INDEX entries_one_running ON entries((stopped_at IS NULL)) WHERE stopped_at IS NULL AND deleted_at IS NULL;
CREATE INDEX entries_started_at ON entries(started_at);
CREATE INDEX entries_client_text ON entries(client_text COLLATE NOCASE);
CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
SQL
  for row in "${ENTRIES[@]}"; do
    IFS='|' read -r day hhmm mins raw <<<"$row"
    h=$((10#${hhmm%%:*})); m=$((10#${hhmm##*:}))
    start=$((MONDAY + day * 86400 + h * 3600 + m * 60))
    (( start < NOW )) || continue                 # never seed the future
    stop=$((start + mins * 60)); (( stop <= NOW )) || stop=$NOW
    # Parse like EntryParser: text before the first " - " is the client, the rest the note;
    # with no separator the whole string is the note and the client is NULL.
    if [[ "$raw" == *" - "* ]]; then client="$(sql_quote "${raw%% - *}")"; note="$(sql_quote "${raw#* - }")"
    else client="NULL"; note="$(sql_quote "$raw")"; fi
    echo "INSERT INTO entries (id, raw_text, client_text, note, started_at, stopped_at, duration_seconds, created_at, updated_at)" \
         "VALUES ('$(uuid)', $(sql_quote "$raw"), $client, $note, $start, $stop, $((stop - start)), $start, $stop);"
  done
  echo "PRAGMA user_version = 1;"
  echo "COMMIT;"
} | sqlite3 "$DB" >/dev/null

echo "Seeded $DB: $(sqlite3 "$DB" 'SELECT count(*) FROM entries;') entries, user_version $(sqlite3 "$DB" 'PRAGMA user_version;')"
