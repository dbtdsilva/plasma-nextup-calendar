# Calendar Picker in Widget Config — Design

**Date:** 2026-06-13
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Let the user choose which calendars the widget shows from the widget's own
configuration dialog, instead of having to open the stock Digital Clock's
calendar settings. This also removes the cold-start confusion where a freshly
added widget shows "No upcoming events" until calendars are enabled somewhere
else.

## Approach decision

**Chosen (Option A): host the `pimevents` plugin's own picker inside our
config dialog.** The plugin ships `PimEventsConfig.qml`, a self-contained
`KCMUtils.ScrollViewKCM` listing Akonadi calendars with checkboxes, exposing
`signal configurationChanged` and `function saveConfig()`. We add a "Calendars"
config category that loads it.

Rejected:

- **Option B — true per-widget independent calendar selection.** Not feasible
  in the pure-QML architecture: `EventDataDecorator` exposes no collection/UID
  (only `eventColor`), so fetched events cannot be filtered by calendar; and
  `pimevents` only delivers events for the globally enabled set. Independent
  selection would require bypassing `pimevents` for direct Akonadi access (C++),
  which loses pure-QML packaging — the architecture rejected in the original
  design.
- **Option C — color-based hide filter.** Limited to the global set, color is
  not a stable per-calendar selector; poor UX.

### Consequence (documented in the UI)

The selection is the **global, shared** `[PIMEventsPlugin] calendars=` set —
the same one the Digital Clock and any other calendar widget use. Changing it
here changes it everywhere. This is inherent to Option A and is surfaced as an
inline note on the page; it is not a per-widget setting.

## Verified facts (target system, Plasma 6.6.4)

- Required QML modules all present: `org.kde.plasma.PimCalendars`,
  `org.kde.kcmutils`, `org.kde.kitemmodels`,
  `org.kde.kirigamiaddons.delegates`.
- `PimEventsConfig.qml` lives at
  `…/qt6/plugins/plasmacalendarplugins/pimevents/PimEventsConfig.qml` and is
  reachable via the `configUi` role on `EventPluginsManager.model` (roles:
  `pluginId`, `checked`, `configUi`, `description`).
- The applet config dialog (`AppletConfiguration.qml`) on **Apply** calls
  `saveConfig()` on the **current page** and connects to the current page's
  `configurationChanged` signal to enable the Apply button. Switching pages
  with unsaved changes triggers the dialog's standard save/discard prompt.
- `ConfigurationContainmentAppearance.qml` is the reference idiom: a config
  page that forwards `configurationChanged` and `saveConfig()` to a hosted
  child item.

## File changes

- `package/contents/config/config.qml` — add a second `ConfigCategory`:
  name "Calendars", icon `office-calendar`, source `configCalendars.qml`.
  The existing "General" category is unchanged.
- `package/contents/ui/configCalendars.qml` — **new**. Responsibilities:
  - Instantiate `PlasmaCalendar.EventPluginsManager`; from its `model`, find
    the row whose `pluginId` contains `pimevents` and read its `configUi` URL.
  - A `Loader` filling the page, `source` set to that URL.
  - `signal configurationChanged()`; a `Connections` on `loader.item` forwards
    the picker's `configurationChanged` to it (enables Apply).
  - `function saveConfig()` calling `loader.item.saveConfig()` when present
    (persists on Apply).
  - A `Kirigami.InlineMessage` (informational) stating the selection is shared
    with other calendar widgets.
  - If no `pimevents` `configUi` is found (kdepim-addons missing) or the Loader
    errors, show an inline message "Install kdepim-addons to choose calendars"
    instead of an empty area.
- `package/contents/config/main.xml` — **unchanged** (picker writes the shared
  `[PIMEventsPlugin]` config, not our `cfg_` entries).
- `package/contents/ui/FullRepresentation.qml` — **unchanged** (no onboarding
  button, per decision).

## Data flow

Configure → **Calendars** → `EventPluginsManager` resolves the `pimevents`
`configUi` → Loader shows the calendar checklist → user toggles a calendar →
picker calls `PimCalendarsModel.setChecked(...)` and emits
`configurationChanged` → our page re-emits it (Apply enables) → on Apply, our
`saveConfig()` → `loader.item.saveConfig()` → `PimCalendarsModel` persists to
the shared `[PIMEventsPlugin] calendars=` → `EventsBackend`'s `pimevents`
plugin delivers the new calendar set on its next `agendaUpdated`/refresh →
events update in panel and popup.

## Error handling

Detected when the page loads:

- `pimevents` `configUi` not found (kdepim-addons not installed) → inline
  message "Install kdepim-addons to choose calendars."
- Loader status `Error` (missing KCM modules) → same inline message; never a
  blank/broken page.

## Testing

- No new pure-JS logic → `eventlogic.js` and its 28 Node tests are untouched;
  run `node --test` as a regression check only.
- Visual + behavioral verification (the blank-popup lesson: verify pixels, not
  just logs), via `plasmoidviewer` config dialog and screenshots:
  1. The "Calendars" category appears alongside "General"; selecting it renders
     the calendar checklist (real Plasma theme).
  2. Toggling a calendar enables Apply; clicking Apply writes the change to the
     `[PIMEventsPlugin] calendars=` config (assert against
     `plasmoidviewerrc`/`plasmashellrc`).
  3. `EventsBackend` reflects the new set (event count changes accordingly).
  4. The General page still loads and saves its existing settings.
  5. kdepim-addons-absent path shows the inline message (simulated by pointing
     at a no-pimevents state).

## Out of scope (this feature)

Per-widget independent calendar selection (Option B); exposing non-PIM calendar
plugins (Holidays, Astronomical Events); an onboarding button from the empty
popup; any change to panel/popup rendering.
