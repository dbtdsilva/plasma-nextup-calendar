# Panel/Popup Filters + Pre-event Alert — Design

**Date:** 2026-06-16
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Give the user control over what the Next Up Calendar widget shows and add an
optional reminder:

1. **Hide all-day events** — independent toggles for the panel ("Next up") and
   the agenda popup, so all-day items (holidays, birthdays, multi-day OOO) can be
   suppressed where they add clutter.
2. **Pre-event alert** — an optional desktop notification that fires once, X
   minutes before the next-up event starts.

## Dropped from scope: "skip non-confirmed events"

The original request also asked to skip non-confirmed (tentative / un-accepted)
events. **This is not implementable with the data the widget receives** and is
deliberately dropped from this change.

The widget reads events through Plasma's shared `pimevents` plugin
(`EventsBackend.qml` → `calendar.daysModel.eventsForDate()`). The event objects
(`CalendarEvents::EventDataDecorator`) expose only:
`startDateTime, endDateTime, isAllDay, isMinor, title, description, eventColor,
eventType`. There is no iCalendar STATUS (CONFIRMED/TENTATIVE/CANCELLED) and no
attendee/RSVP field (ACCEPTED/DECLINED/NEEDS-ACTION). Verified against the
installed `calendarplugin.qmltypes` and by confirming `pimevents.so` /
`libcalendarplugin.so` contain no `tentative`/`partstat`/`attendee` strings.
`eventType` only distinguishes `Holiday | Event | Todo | Journal`.

Implementing a real confirmed-filter would require reading Akonadi /
KCalendarCore directly to get each event's attendee PARTSTAT — a significant new
dependency and a departure from the shared-plugin architecture the widget uses
on purpose. Left for a future change if a data source becomes available.

## Feature 1: Hide all-day events (separate panel + popup toggles)

### Config (`config/main.xml`, group `General`)

- `panelHideAllDay` (Bool, default `false`) — hide all-day events in the panel.
- `popupHideAllDay` (Bool, default `false`) — hide all-day events in the popup.

Both default `false` so existing installs are unchanged.

### Logic (`js/eventlogic.js`, pure + Node-tested)

- **`selectPanelEvent(events, now, opts)`** — when `opts.hideAllDay` is true, skip
  the all-day fallback branch. The `ongoing` and `upcoming` branches already
  filter to timed events (`!e.isAllDay`), so the only place an all-day event can
  surface for the panel is the third (fallback) branch. Gating that branch means
  the panel returns `{ kind: "none" }` when no timed event is in the window. One-
  line change; no effect when `hideAllDay` is false/absent.
- **`groupByDay(events, now, opts, weekdayName)`** — when `opts.hideAllDay` is
  true, drop `isAllDay` events from each day's list (filter before the existing
  empty-day `continue`, so a day with only all-day events produces no group).

### Wiring

- `main.qml` `refresh()` passes `hideAllDay: cfg.panelHideAllDay` into
  `selectPanelEvent`.
- `main.qml` passes `hideAllDay: Plasmoid.configuration.popupHideAllDay` to the
  `FullRepresentation`.
- `FullRepresentation.qml` gains `property bool hideAllDay`, re-runs `rebuild()`
  on change (`onHideAllDayChanged: rebuild()`), and passes
  `hideAllDay: hideAllDay` into the `groupByDay` opts.

## Feature 2: Optional pre-event alert

A standard KDE desktop notification, fired once, X minutes before the **next-up
timed event** (the same event the panel shows). Because it keys off the panel
selection, it automatically inherits the panel's `lookahead` window and the
`panelHideAllDay` filter.

### Config (`config/main.xml`, group `General`)

- `alertEnabled` (Bool, default `false`) — opt-in; firing notifications by
  default would surprise users.
- `alertMinutesBefore` (Int, default `5`) — how many minutes ahead to notify.

### Decision logic (`js/eventlogic.js`, pure + Node-tested)

Keep the side-effect-free decision in the logic file (matching
`selectPanelEvent`/`formatPanelText`); the actual `sendEvent()` lives in QML.

- Extract a helper **`eventKey(e)`** = `e.title + "|" + e.startDateTime.getTime()`
  and reuse it inside `dedupe` (no behavior change — same key string `dedupe`
  builds today).
- New **`evaluateAlert(selection, now, opts, lastAlertedKey)`** → `{ fire, key }`:
  - `opts` = `{ alertEnabled, alertMinutesBefore }`.
  - Returns `{ fire: false, key: lastAlertedKey }` unless **all** hold:
    `alertEnabled` is true; `selection.kind === "upcoming"`; minutes-until-start
    (`Math.ceil((event.start - now) / 60000)`) `<= alertMinutesBefore`; and
    `eventKey(event) !== lastAlertedKey`.
  - When all hold: returns `{ fire: true, key: eventKey(event) }`.
  - The `selection.kind === "upcoming"` guard means `start > now`, so a started
    event (`ongoing`), an all-day fallback, or `none` never alert.

This fires exactly once per event: after firing, `lastAlertedKey` holds that
event's key, so subsequent 30s refreshes within the same window return
`fire: false`. The next distinct event has a different key and becomes eligible.

### QML wiring (`main.qml`)

- `import org.kde.notification`.
- A `Notification { componentName: "plasma_workspace"; eventId: "notification" }`
  (the generic ad-hoc-notification event; no custom `.notifyrc` needed).
- `property string lastAlertedKey: ""`.
- In `refresh()`, after computing `selection`:
  ```js
  const alert = Logic.evaluateAlert(selection, now,
      { alertEnabled: cfg.alertEnabled, alertMinutesBefore: cfg.alertMinutesBefore },
      root.lastAlertedKey);
  root.lastAlertedKey = alert.key;
  if (alert.fire) { /* set notification.title/text, sendEvent() */ }
  ```
  The notification text is the event title + a "in X min" / start-time line
  (reusing the same minute math). `refresh()` is already called on the 30s timer,
  on `eventsChanged`, and on config changes; `lastAlertedKey` prevents repeats
  across all of these.

### Config UI (`configGeneral.qml`)

Regroup the `Kirigami.FormLayout` into three sections using
`Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label }`,
mirroring the request:

- **Next up (panel):** existing `lookahead`, `maxTitleLength`,
  `urgentThresholdMinutes`, `placeholderText` controls + a new
  `QQC2.CheckBox` "Hide all-day events" (`cfg_panelHideAllDay`).
- **Agenda popup:** existing `popupDays` + a new `QQC2.CheckBox`
  "Hide all-day events" (`cfg_popupHideAllDay`).
- **Alert:** `QQC2.CheckBox` "Notify before the next event" (`cfg_alertEnabled`)
  + `QQC2.SpinBox` "Minutes before:" (`cfg_alertMinutesBefore`, range 1–120),
  the spinbox `enabled: alertEnabledCheck.checked` so it greys out when off.

New config-page properties: `cfg_panelHideAllDay`, `cfg_popupHideAllDay`,
`cfg_alertEnabled` (CheckBox `checked` aliases) and `cfg_alertMinutesBefore`
(SpinBox `value` alias) — standard `cfg_` properties persisted by the dialog.

## Data flow

`refresh()` (30s timer / events change / config change) → `selectPanelEvent`
(now honoring `panelHideAllDay`) → `formatPanelText` for the panel label →
`evaluateAlert` → `sendEvent()` when it flips to `fire`. The popup's `rebuild()`
→ `groupByDay` (now honoring `popupHideAllDay`) → agenda model.

## Error handling

- `alertMinutesBefore` is bounded by the SpinBox (1–120); no zero/negative path.
- If `alertEnabled` is false, `evaluateAlert` short-circuits to `fire: false`.
- Edit/restart: `lastAlertedKey` is in-memory and resets on widget reload —
  worst case is one extra notification for an event already inside the window,
  which is acceptable and self-corrects.
- Notification subsystem unavailable: `sendEvent()` is a no-op at the platform
  level; the panel/popup are unaffected.

## Testing

`tests/eventlogic.test.js` (Node, `node --test`) gains cases:

- `selectPanelEvent` with `hideAllDay: true` suppresses the all-day fallback
  (an all-day-only set → `kind: "none"`); with `hideAllDay` false/absent the
  all-day fallback still works (existing tests stay green).
- `groupByDay` with `hideAllDay: true` drops all-day rows and omits a day that
  had only all-day events; mixed days keep their timed events.
- `evaluateAlert`: disabled → no fire; upcoming within threshold, first time →
  `fire: true` with the event key; same event already alerted → no re-fire;
  upcoming beyond threshold → no fire; non-upcoming (`ongoing`/`allday`/`none`)
  → no fire; a new distinct event after a previous alert → fires for the new key.
- `eventKey` produces the same string `dedupe` relied on (regression guard for
  the extraction).

QML wiring (config UI, notification send, popup/panel filtering) is verified
visually/behaviorally via the QML harness — no new pure logic lives in QML.

## Out of scope

- Skipping non-confirmed / tentative / un-accepted events (see "Dropped from
  scope" — data unavailable).
- Alerting for events other than the single next-up event.
- Notification action buttons (e.g. a "Join" link); the alert is a plain
  notification. Can be added later.
- Sound configuration beyond whatever the user's notification settings apply.
- Persisting alert state across widget reloads.
