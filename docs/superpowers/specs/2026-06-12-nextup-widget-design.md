# Next Up Calendar — Plasma Widget Design

**Date:** 2026-06-12
**Status:** Approved (first version scope)
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

A KDE Plasma 6 panel widget that shows the next upcoming calendar event as text
in the panel — the Plasma equivalent of GNOME's "Next Up" extension. Events come
from Akonadi (the storage used by Merkuro / KOrganizer), so any account synced
there works, including the user's Office365 account. No 1:1 equivalent exists in
the Plasma ecosystem today; existing widgets (Event Calendar and its Plasma 6
ports) only show agendas in a popup.

## Approach decision

**Chosen: Pure QML plasmoid using Plasma's calendar framework**
(`org.kde.plasma.workspace.calendar`): `EventPluginsManager` with the
`pimevents` plugin (from kdepim-addons) enabled programmatically, a `Calendar`
backend, and `DaysModel.eventsForDate(date)` to read events. This is the same
machinery the stock Digital Clock popup uses.

- No compilation; installable with `kpackagetool6`, distributable on the KDE Store.
- Reads exactly what Merkuro writes to Akonadi.
- Verified on the target system (Plasma 6.6.4): all required types are
  QML-exported and `pimevents.so` is installed.
- Known risk: the QML module is semi-internal (versioned 2.0, consumed by
  plasma-workspace itself); a future Plasma release could change it. Accepted —
  it has been stable across Plasma 5 → 6.

Rejected alternatives:

- **CLI bridge** (konsolekalendar or scripts, polled): binary not installed,
  fragile text parsing, polling.
- **Compiled C++ applet** (Akonadi-Calendar/ETMCalendar): per-distro builds,
  cannot ship as a pure package on the KDE Store, much higher effort.

## Package layout

Plugin ID: `com.github.dbtdsilva.nextupcalendar`

```
package/
  metadata.json
  contents/
    ui/main.qml                  # PlasmoidItem wiring compact/full representations
    ui/CompactRepresentation.qml # panel text
    ui/FullRepresentation.qml    # agenda popup
    ui/EventsBackend.qml         # Calendar + EventPluginsManager + refresh timers
    ui/configGeneral.qml         # settings UI
    config/main.xml              # config schema
    js/eventlogic.js             # all decision logic as pure functions
tests/                           # node-run unit tests for eventlogic.js
install.sh
README.md
LICENSE                          # GPL-2.0-or-later
```

## Data flow

1. `EventsBackend.qml` creates an `EventPluginsManager`, enables `pimevents`
   via `populateEnabledPluginsList`, and a `Calendar` with
   `displayedDate = today`.
2. On the `agendaUpdated(date)` signal it collects
   `daysModel.eventsForDate(today)` and `eventsForDate(tomorrow)` (and further
   days for the popup window).
3. Events are deduplicated (multi-day events appear under several dates; the
   decorator exposes no UID, so dedupe key is `title + startDateTime`).
4. A 30-second timer re-evaluates panel text (countdowns); a midnight handler
   advances `displayedDate` and re-queries.

`EventDataDecorator` fields available: `startDateTime`, `endDateTime`,
`isAllDay`, `isMinor`, `title`, `description`, `eventColor`, `eventType`.
There is **no location or URL field** — meeting-link detection uses
`description` only.

## Panel selection and formatting

Window: **today + tomorrow** (default; configurable). Priority order:

1. **Ongoing timed event** → `Standup · ends 15:30`
2. **Next timed event** →
   - ≤ 60 min away: `Standup · in 12 min` (urgent color at ≤ 5 min, threshold configurable)
   - later today: `Standup · 14:30`
   - tomorrow: `Standup · tomorrow 09:00`
3. **All-day event** (only when no timed event is pending) →
   `Holiday · all day` / `Holiday · tomorrow`
4. **Nothing** → placeholder text `No upcoming events` (configurable)

Timed events outrank all-day events for the panel slot. Titles are ellipsized
at a configurable max length (default 30 chars).

## Popup (full representation)

Agenda of the next 7 days (count configurable), grouped by day with headers
"Today", "Tomorrow", then weekday names. Each row: calendar color dot, time
range (`14:30–15:00` or `All day`), title. All-day events pinned at the top of
each day group. Footer button opens Merkuro. Days without events are omitted.

## Click behavior

- Panel click → toggle popup (standard plasmoid behavior).
- Event row click → scan `description` for a meeting URL, first match opens in
  browser; otherwise open Merkuro (`merkuro-calendar`).
- Recognized providers: Teams (`teams.microsoft.com/l/meetup-join`), Google
  Meet (`meet.google.com`), Zoom (`zoom.us/j/`).
- Degradation: if Office365 carries the link only in the (unavailable) location
  field, the click falls back to opening Merkuro.

## Configuration options

| Option | Default |
|---|---|
| Lookahead window | today + tomorrow (alternatives: today only, 24 h rolling) |
| Max title length | 30 chars |
| Urgent threshold | 5 min |
| Placeholder text | "No upcoming events" |
| Popup days | 7 |

## Error handling

Detected at backend init and surfaced in the popup (panel shows placeholder):

- `pimevents` plugin not installed → hint "Install kdepim-addons".
- Akonadi not running → hint to start it / open Merkuro.

## Testing strategy

- **TDD with Node** on `eventlogic.js` pure functions: `dedupe`,
  `selectPanelEvent`, `formatPanelText`, `groupByDay`, `findMeetingUrl`,
  `timeRangeText`. The file carries a `typeof module !== 'undefined'` export
  guard so the identical file loads in QML (`import "../js/eventlogic.js"`)
  and in Node tests.
- **Manual verification** in `plasmoidviewer`, then real-panel install via
  `install.sh` (kpackagetool6 install/upgrade + plasmashell refresh hint).

## Out of scope (first version)

- Google/CalDAV access without Akonadi, notifications/reminders, snooze,
  per-calendar filtering, Plasma 5 support, KDE Store packaging automation.
