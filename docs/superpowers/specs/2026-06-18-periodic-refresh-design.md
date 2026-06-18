# Periodic Calendar Refresh + Last-Refresh Readout — Design

**Date:** 2026-06-18
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

New events created on the server (e.g. Exchange/EWS, via another device or the
web) don't reach the widget until Akonadi syncs the resource — which, with EWS
push-subscription mode, can stall until a manual "Update Calendar" in Merkuro.
(Investigation confirmed this is an Akonadi-resource sync gap, not a widget bug:
Merkuro's own view is equally stale until a forced sync.) This feature makes the
widget force that sync on a timer, shows when it last refreshed, and tidies the
popup footer.

Three parts:
1. **Periodic refresh** — on an interval, force a sync of the calendar Akonadi
   resource(s) (what Merkuro's "Update Calendar" does).
2. **Last-refresh readout** — show `Updated HH:MM` at the bottom-left of the popup.
3. **Footer rearrange** — move the settings cog next to "Open Merkuro" on the right.

## Feature 1: Periodic refresh

### Config (`config/main.xml`)

- New entry **`refreshIntervalMinutes`** (Int, default **3**). `0` disables the
  periodic refresh. UI range 0–240.

### Where it lives

`EventsBackend.qml` (it owns calendar data and must run regardless of whether the
popup is open). It gains `property int refreshIntervalMinutes`, fed from config by
`main.qml` (`refreshIntervalMinutes: Plasmoid.configuration.refreshIntervalMinutes`),
the same way `pluginEnabled`/`daysAhead` are.

### Mechanism

- A `Timer`:
  - `interval: Math.max(1, refreshIntervalMinutes) * 60000`
  - `running: refreshIntervalMinutes > 0 && pluginEnabled`
  - `repeat: true`, `triggeredOnStart: true` (so a fresh sync also happens shortly
    after load / whenever the interval changes)
  - `onTriggered: backend.syncCalendars()`
- `syncCalendars()` connects a `P5Support.DataSource { engine: "executable" }`
  (same pattern as the popup's `openMerkuro()`), with `onNewData` disconnecting the
  source, running this `sh` command (validated locally — it targets only the EWS
  calendar resource and skips mail/contacts/agents):

  ```sh
  QDBUS=$(command -v qdbus6 || command -v qdbus); [ -n "$QDBUS" ] || exit 0
  for id in $("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstances); do
    t=$("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstanceType "$id")
    case "$t" in
      akonadi_ews_resource|akonadi_davgroupware_resource|akonadi_google_resource|akonadi_ical_resource|akonadi_icaldir_resource|akonadi_openxchange_resource|akonadi_kalarm_resource)
        "$QDBUS" org.freedesktop.Akonadi.Resource."$id" / org.freedesktop.Akonadi.Resource.synchronize ;;
    esac
  done
  ```

  In QML this is held as one single-quoted string constant (it contains only
  double quotes internally, so it embeds cleanly).

- **No new data path:** forcing `synchronize()` makes Akonadi fetch from the
  server → the pimevents plugin signals `agendaUpdated` → the existing `collect()`
  re-reads and updates `upcomingEvents`/the UI. Nothing downstream changes.

### Resource discovery

Auto-discovered by agent **type** each run (no stored resource id, portable across
machines): the calendar resource types above. Pure mail/contacts resources
(`akonadi_maildir_resource`, `akonadi_contacts_resource`, imap/pop3) are skipped.
Combined accounts (EWS/Google/DAV) sync their whole account, which is fine.

## Feature 2: Last-refresh readout

- `EventsBackend` sets `property var lastRefresh` to `new Date()` at the end of a
  successful `collect()` (i.e. when `pluginEnabled` and events were re-read). It
  stays unset while events are disabled / before the first read.
- `main.qml` passes `lastRefresh: backend.lastRefresh` to `FullRepresentation`.
- The footer renders `i18n("Updated %1", Qt.formatTime(lastRefresh))` when set,
  else an empty string — muted, small font (like the agenda row's time text).
  (Claude's widget shows `Updated: HH:MM:SS`; minute precision is enough here.)

## Feature 3: Footer rearrange (`FullRepresentation.qml`)

The footer `RowLayout` changes from `[cog] —spacer— [Open Merkuro]` to:

```
[ Updated HH:MM ]      —(fillWidth spacer)—      [⚙ Configure] [ Open Merkuro ]
```

- Left: the last-refresh `PlasmaComponents.Label`.
- `Item { Layout.fillWidth: true }` spacer.
- The existing configure (cog) `Button`, then the "Open Merkuro" `Button` — so the
  cog sits just left of Merkuro, Merkuro stays rightmost (primary action). Both
  buttons' behavior is unchanged.

## Config UI (`configGeneral.qml`)

A new section at the end:

```
Kirigami.Separator { isSection; label: "Calendar refresh" }
QQC2.SpinBox {
    id: refreshInterval            // cfg_refreshIntervalMinutes
    FormData.label: "Refresh calendars every (minutes), 0 = off:"
    from: 0; to: 240
}
```

Plus the `property alias cfg_refreshIntervalMinutes: refreshInterval.value`.

## Data flow

`refresh Timer` (every N min, + on start) → `syncCalendars()` → executable
DataSource runs the qdbus loop → Akonadi syncs the calendar resource(s) from the
server → pimevents → `daysModel.agendaUpdated` → existing `collect()` →
`upcomingEvents` updated + `lastRefresh = new Date()` → panel/popup update; the
footer's "Updated HH:MM" reflects the new `lastRefresh`.

## Error handling

- No `qdbus6`/`qdbus` on PATH → the command `exit 0`s (no-op).
- No calendar resource matched → loop does nothing.
- DataSource: disconnect the source `onNewData` (as `openMerkuro()` does) so it can
  run again next interval; output is ignored (fire-and-forget).
- Throttling: default 3 min is within EWS limits; the interval is user-configurable
  and `0` disables it.
- `running` is gated on `pluginEnabled`, so a disabled integration triggers no
  syncs.

## Testing

No new pure-JS logic (the feature is QML wiring + a shell command + config), so the
37 Node tests are unaffected and remain the regression gate. Verification:
- The discover-and-sync command's discovery half was validated locally (targets
  only the calendar resource).
- CI's `validate` job runs `qmllint` over the changed QML on push.
- Visual: install + restart; confirm the footer shows "Updated HH:MM" and the cog
  sits next to "Open Merkuro"; create an event server-side and confirm it appears
  within the interval without a manual "Update Calendar".

## Out of scope

- A manual "refresh now" button.
- Per-resource selection / a configurable resource-type list.
- Relative "x minutes ago" text (absolute `Updated HH:MM`, matching Claude).
- Fixing akonadi-ews's push-subscription staleness upstream (we work around it by
  forcing periodic syncs).
