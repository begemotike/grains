# MCP server and AI agents

AI is the interpreter, not the timekeeper. `grains-mcp` gives Claude (and, with a bridge, ChatGPT) read-only access to records and deterministic aggregates. Every number comes from `GrainsReports`, never from the model.

## Process

`Grains.app/Contents/MacOS/grains-mcp`: a tool target in the Xcode project, built from `Sources/grains-mcp/main.swift`, which calls `GrainsMCP.Server.runStdio(store:)`. Opens the database read-only (`GRAINS_DB_PATH` honored). Logs to stderr only (stdout is the protocol channel). Exit code 2 when the database does not exist (with a message telling the user to launch Grains once).

## Protocol

MCP over stdio, JSON-RPC 2.0, newline-delimited, protocol version `2025-06-18`. Implemented by hand in `GrainsMCP` (no SDK dependency; the subset needed is small): `initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`, `resources/list` (none), `prompts/list` (none). Unknown methods → `-32601`. Tool errors are returned as `isError: true` results with a readable message, not as protocol errors.

## Tools (binding; all read-only)

| Tool | Input | Output |
|---|---|---|
| `list_sessions` | `from`, `to` (RFC 3339 or `YYYY-MM-DD`, local), optional `client`, `limit` (default 200) | entries overlapping the range, with the clipped seconds for the range and whole duration |
| `get_session` | `id` | one entry or not-found error |
| `search_sessions` | `query`, `limit` | substring match over raw text/client/note |
| `aggregate` | `from`, `to`, `group_by`: `day`\|`week`\|`client`\|`client_day` | rows with `key`, `seconds`, `hours`, `entry_count`; totals computed by `GrainsReports` |
| `list_client_labels` | none | distinct `client_text` with counts and total hours; entries with no client appear as `null` so the model can propose matches |
| `current_week` | optional `target_hours` | `WeekSeries` summary: week id, interval, total hours, elapsed fraction, hours per day |
| `running_session` | none | the running entry and its elapsed seconds, or null |
| `list_exports` | none | export folder and the CSV files present (name, week, size, modified) |
| `export_week` | `week` (`2026-W44`) | **not** a write to the database: returns the CSV text for that week computed on the fly, so an agent can build a timesheet without touching the export folder |

Every result that contains times carries them as RFC 3339 with offset **and** includes `time_zone` so the model never guesses. Every tool description states the Grains conventions ("`client_text` is a provisional label typed by the user; it may be a typo or an alias").

## Privacy and permissions

- Read-only database handle; there is no write tool. Future edit tools must require explicit approval in the Grains UI (roadmap).
- The server exposes only what the tools return. No file system access beyond the database and listing the export folder.
- Notes may contain client names; the server has an opt-in `--redact-notes` flag (Settings → "Share notes with AI": off hides `note` and returns only `client_text` and durations).

## Client setup

**Claude Code**

```bash
claude mcp add grains -- /Applications/Grains.app/Contents/MacOS/grains-mcp
```

**Claude Desktop**: add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{ "mcpServers": { "grains": { "command": "/Applications/Grains.app/Contents/MacOS/grains-mcp" } } }
```

Settings → "Copy Claude configuration" puts the right snippet on the clipboard with the real path of the running app.

**ChatGPT**: ChatGPT connectors (and the Apps SDK) connect to *remote* MCP servers over HTTPS with OAuth or no auth; they cannot reach a process on your Mac. v1 therefore does not claim ChatGPT support out of the box. Two documented paths: (1) run `grains-mcp --http 127.0.0.1:7421` (Streamable HTTP transport) and publish it through a tunnel you control (Cloudflare Tunnel, Tailscale Funnel) with the connector's bearer token in the tunnel config; (2) paste the `export_week` CSV into ChatGPT. The HTTP transport is in the roadmap and off by default.

## What agents may do

Answer questions, build timesheets, propose client merges, summarize days, draft QuickBooks-ready exports from `export_week`. They may not change records. Example prompts live in [roadmap.md](roadmap.md) for the future approval-gated edit tools.
