# Blink — macOS Time Tracker

**Product concept and initial implementation brief**  
**Status:** Design and engineering specification, v0.1  
**Primary reference:** [Monkeytype](https://monkeytype.com/) — typography, restrained interaction, motion, and especially the graphs.

## Vision

Blink is a native, keyboard-first macOS time tracker designed to make recording work almost instantaneous. It is a capture tool, not a project manager or accounting system.

**Capture first. Organize later.** Summon a floating layer, type what you're doing, start or stop the clock, and return to work. Blink preserves the raw data. Claude and ChatGPT integrations interpret, reconcile, and report it afterward.

The application should feel closer to Spotlight, Raycast, and Monkeytype than to a conventional timesheet application.

## Core interaction

- A configurable **global keyboard shortcut** summons a small floating overlay above the active app.
- Moving the pointer into a **configurable screen corner** can summon the same overlay. The corner trigger needs sensible dwell/debounce and should avoid interfering with system Hot Corners.
- **Typing works immediately** upon opening: no clicking a field, no Tab, no field selection.
- There is **one text-entry surface**. No required client selectors, dropdowns, task hierarchy, or billing fields.
- A single entry takes the form `Client - note`, for example:
  - `Global Credit Union - Jamf certificate troubleshooting`
  - `Denali - iPad enrollment issue`
  - `Spruce - Policy engine`
  - `Administrative work`
- Parse the text before the first ` - ` as a provisional client label and the remainder as a note. The separator is optional. Do **not** require a client to exist beforehand, and always preserve the original exact string.
- **Spacebar is the preferred instantaneous start/stop control**, but it must also work normally for entering spaces inside text. This is a key design problem, not something to hand-wave. A recommended interaction to prototype:
  - **Control mode** (overlay focused, not editing): Space toggles timer.
  - **Typing mode** (begins on first printable character): Space inserts a space; Return commits the entry and starts or changes the timer, returning to control mode.
  - Escape dismisses overlay without ending the timer.
  - The active mode must be unambiguous and switching modes must not require clicking or selecting an input field. Explore alternatives in the UI prototype if they prove faster.
- Starting a new entry while a timer runs automatically ends the previous session and starts the new one. Only one timer may run at a time in v1.
- Closing the overlay, changing apps, or locking the computer must not stop an active timer.

## Interface direction: Monkeytype, heavily

Typography is the product's main visual element. The floating overlay should feel like a beautifully designed text editor with live timing feedback, not a productivity dashboard.

- Large, crisp entry text and a smoothly animated caret.
- Subtle typographic or color distinction between the provisional client, delimiter, and note, while preserving one continuous editable line.
- Minimal chrome: no outlined form fields or competing buttons in the primary view.
- Dark theme first, restrained accent colors, highly legible numerals and labels, polished motion that never delays key input.
- Fast entrance/exit with immediate keyboard readiness.
- Modest menu-bar presence for secondary access, settings, and status.
- Three essential visual states: **idle**, **typing**, **timer running**. Also design a **timer paused/stopped** state and a **switching entry** transition.

### Suggested visual hierarchy

1. Main text entry / current entry.
2. Running status and current session elapsed time.
3. Weekly activity graph.
4. Small typographic metrics (today, week, optionally current session).
5. Secondary controls and historical navigation.

## Weekly graph — a signature feature

The compact chart beneath the entry is part of Blink's main overlay, **not a separate reports screen**. Inspired by Monkeytype's results graphs, it makes the passing workweek visible without adding UI friction.

At the beginning of each week (Monday by default), the chart starts at zero and unfolds through the week.

### Primary series: tracked hours

- **X-axis:** elapsed calendar time across the seven-day week.
- **Y-axis:** cumulative tracked hours.
- While a session is running, the tracked-hours line rises.
- While the timer is stopped, the line stays flat.
- The actual series ends at **now**; do not extend actuals into the future.
- Backdated corrections update the curve historically and deterministically.
- The accumulated total should update in real time or near-real time.

### Second series: available/elapsed time

Show a restrained second line that advances with clock time. Its purpose is to visualize the relationship between **hours worked** and **time passing**. This is distinct from an arbitrary 40-hour goal.

**Important:** A raw seven-day clock line reaches 168 hours and can visually squash a 20–50-hour tracked-hours series. Design an honest, clearly labeled comparison rather than silently mixing incompatible scales. Prototype options include a shared scale with thoughtful framing, an explicitly labeled secondary scale, or an aligned two-lane graph. Decide based on readability and truthful interpretation.

An optional **target trajectory** (e.g., 40 hours over a configured workweek) can be a third, muted reference, but must never be confused with either actual tracked hours or elapsed clock time.

### Chart details

- Compact, understated grid/axes; legible weekday markers.
- Smooth line drawing and a small active point at the current moment.
- Clear differentiation between actual, elapsed time, and optional target.
- Distinguish past, present, and future.
- Weekly rollover automatically starts a new chart; previous weeks remain accessible.
- Use local calendar/time-zone semantics for week boundaries, with robust handling of daylight saving and travel.
- Support correct charting if a session crosses midnight or a week boundary; do not lose or double-count elapsed time.

### Supporting statistics

Monkeytype-style typography for concise metrics such as:

- **23.7** — tracked hours this week
- **4.8** — tracked hours today
- **01:43:29** — current session

These are calculated from stored entries, not estimated by AI. Figures and graph should be derived from the same source of truth.

### Future visualization ideas (not v1 requirements)

Daily hours for the past seven days; stacked time by client; session timeline; comparison of past weeks; work rhythms and break lengths. Keep these secondary to the principal weekly view.

## Timer and storage rules

- Persistent, local-first storage; **SQLite** is suitable.
- The timer engine must be independent of overlay visibility.
- Save start and stop events immediately; keep active timer state recoverable after crashes or restarts.
- Store absolute timestamps for durable records, with monotonic timing where appropriate to make live elapsed-time displays resilient to clock changes.
- Define recovery behavior after unexpected shutdown or reboot without inventing silently tracked time. Flag uncertain intervals for reconciliation.
- Track sessions independently; do not overwrite original records during client reconciliation.

Proposed entry fields:

| Field | Purpose |
| --- | --- |
| `id` | Stable unique ID |
| `raw_text` | Original user-entered text, unchanged |
| `client_text` | Provisional client portion, optional |
| `note` | Parsed note, optional |
| `client_id` | Optional normalized client ID |
| `started_at` | Absolute timestamp |
| `stopped_at` | Absolute timestamp or null while running |
| `duration_seconds` | Deterministically computed elapsed duration |
| `created_at` | Record creation |
| `updated_at` | Last modification |
| `metadata` | Extensible optional data |

Clients can be normalized later through alias matching or AI, but entry capture must never depend on it.

## Weekly CSV exports

Maintain reproducible, portable weekly CSV exports in a user-chosen folder, named for example `Blink-2026-W44.csv` (ISO week numbering). Include entry IDs, raw text, parsed client/note, normalized client ID if available, timestamps, and duration.

- Database remains canonical; CSV is an export.
- Each completed week should be exported automatically. Clearly define whether the current week's CSV is updated continuously or on a schedule.
- A correction to a prior week should regenerate that week's export.
- Use a documented CSV schema and clear time-zone handling.
- Prefer atomic write/replace to avoid partial exports.
- Preserve enough detail to support import into billing and reporting systems.

## Claude and ChatGPT integration

AI is an interpreter, **not the timekeeper**. The application must calculate dates, durations, and totals deterministically.

Build a local, permission-conscious **MCP server** exposing records and summaries. Claude/Claude Code integration is a primary target. ChatGPT integration should use the currently supported connector/app or MCP mechanism; verify platform transport, authentication, and local-server accessibility rather than assuming that all ChatGPT surfaces can directly connect to a localhost server.

Initial operations (read-only):

- List sessions by date range.
- Fetch an entry by ID.
- Search raw descriptions and client text.
- Aggregate by day/week/client.
- List unknown or ambiguous client labels.
- Produce or locate CSV exports.

Example questions:

- “How many hours did I work for Global Credit Union this week?”
- “Build my billable October timesheet.”
- “Which entries probably belong to the same client?”
- “Summarize everything I worked on yesterday.”
- “Prepare an export suitable for QuickBooks.”

Future AI-assisted edits, client matching, and categorization should require explicit approval, be auditable, and never discard raw input. Expose only necessary data, keep sensitive client descriptions private by default, and make permissions clear.

## Technical direction

- **Platform:** native macOS.
- **Language/UI:** Swift, SwiftUI; use AppKit where necessary for an always-ready floating panel, event handling, focus control, and global shortcuts.
- **Timing and persistence:** a reliable app-level timer engine backed by SQLite.
- **Corner activation:** macOS-compatible pointer/corner observation with accessibility and permission implications evaluated during implementation.
- **Exports:** local CSV writer with scheduled/triggered updates.
- **Integration:** MCP server and appropriate Claude/ChatGPT adapters.
- **Architecture:** a shared core data/timer layer consumed by overlay, optional menu bar UI, exporter, and MCP service.
- **Scope:** no compulsory cloud account, subscription, project hierarchy, or remote backend in v1.

Evaluate macOS launch-at-login, full-screen spaces, multiple displays, secure input restrictions, sleep/wake, focus-stealing limits, and conflicts with existing Hot Corners/global shortcuts.

## Version 1 boundaries

**Ship:** global shortcut, optional corner summon, single-line text-first overlay, clear Space/typing behavior, one active timer, persistent local records, weekly dual-series visual, small live stats, CSV exports, and read-only MCP interface.

**Defer:** invoicing, elaborate client directories, billing rates, automatic AI categorization during capture, cloud sync, complicated settings screens, and full project management.

## Development handoff

### Codex — interface design and prototype

Design a high-fidelity, Monkeytype-inspired native macOS overlay. Prototype idle, typing, running, stopped, and entry-switching states. Resolve keyboard mode conflicts with priority on instantaneous use. Show the weekly graph with **actual tracked time** and **elapsed/available time** without misleading scales. Specify typography, chart geometry, palette, motion, key commands, accessibility, and multi-display placement.

Deliver UI flows and a working prototype or implementation-ready design spec for Claude Code.

### Claude Code — application implementation

Implement the UI specification in native Swift/SwiftUI/AppKit; build the reliable timer lifecycle, SQLite persistence, weekly CSV export service, weekly chart computations, and read-only MCP server. Keep the core independently testable and avoid coupling capture to network services.

### Validation

Test start/stop with no mouse use; typing spaces; rapid switching; dismiss/reopen; long sessions; clock changes; sleep/wake; restart and crash recovery; sessions crossing midnight/week boundaries; correct weekly totals; previous-week edits; complete CSV regeneration; MCP read consistency; full-screen apps and multiple monitors.

## Nonnegotiable product principles

1. **Capture first; organize later.**
2. **Typing is immediate.** No field selection.
3. **One text entry surface.**
4. **Start/stop must be nearly effortless.** Preserve normal text input.
5. **The weekly graph is integral to the overlay.**
6. **Local data ownership and portable CSV.**
7. **Deterministic timing, AI interpretation.**
8. **No UI complexity in exchange for advanced features.**

**Product statement:** Blink is a time tracker that gets out of the way. Summon it, type what you're doing, start the clock, and forget about it. Blink remembers the time; AI figures out what to do with it.
