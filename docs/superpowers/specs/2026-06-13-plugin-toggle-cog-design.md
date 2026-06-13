# PIM Events Toggle + Settings Cog — Design

**Date:** 2026-06-13
**Status:** Approved
**Repo:** https://github.com/dbtdsilva/plasma-nextup-calendar

## Purpose

Two UX improvements for the Next Up Calendar widget:

1. **Calendars page:** make the dependence on the PIM Events plugin explicit and
   controllable — a real enable/disable switch for the calendar-events
   integration, the calendar picker gated (disabled) when the integration is
   off, and clear install guidance when the plugin is not installed.
2. **Popup footer:** a settings cog button next to "Open Merkuro" that opens the
   widget's own configuration dialog.

## Feature 1: PIM Events enable toggle + gating + install help

### Behavior change

Today `EventsBackend.qml` unconditionally force-enables the `pimevents` plugin
at runtime (`enabledPlugins = [pimPluginId]`), so the integration is always on.
To make a real toggle meaningful, the widget instead **respects a persisted
per-widget switch**.

- New config entry **`pimEventsEnabled`** (bool) in `config/main.xml`,
  **default `true`**. Default-on preserves current behavior for existing
  installs (KConfigXT applies the default when the key is absent), so nothing
  regresses.
- `EventsBackend.qml` gains a `property bool pluginEnabled` (no new import; it
  does not read `Plasmoid` itself). `main.qml` — which already owns `Plasmoid` —
  binds it: `pluginEnabled: Plasmoid.configuration.pimEventsEnabled`. The
  backend enables `pimevents` only when `pluginEnabled` is true. On
  `onPluginEnabledChanged`: if true and the plugin is available, enable and
  re-collect; if false, set `enabledPlugins = []`, clear `upcomingEvents`, and
  emit `eventsChanged()` (panel + popup fall back to the empty state).
  `enablePimPlugin()` becomes guarded by `pluginEnabled`.

This is the per-widget, persisted representation of "show calendar events." We
do not reuse the plugin model's `checked` role (it is per-manager-instance and
not persisted by us); a config bool is the single source of truth.

### Calendars page states (`configCalendars.qml`)

The page keys off two facts: `pimConfigUi !== ""` (plugin installed) and
`cfg_pimEventsEnabled` (integration on).

1. **Plugin not installed** (`pimConfigUi === ""`): a `Kirigami.PlaceholderMessage`
   (centered) with install guidance — title "Calendar selection unavailable",
   explanation "Calendar events require the PIM Events plugin from the
   kdepim-addons package. Install it with your distribution's package manager,
   then reopen settings." The toggle is not shown in this state.
2. **Installed, integration on:** a switch at the top —
   `QQC2.Switch`/`CheckBox` "Show calendar events (PIM Events plugin)" bound to
   `cfg_pimEventsEnabled` — then the existing shared-set `InlineMessage`, then
   the calendar picker (`Loader`), fully interactive.
3. **Installed, integration off:** the switch shows off; the calendar picker is
   `enabled: false` (greyed) with a hint that the plugin must be enabled to
   choose calendars.

`cfg_pimEventsEnabled` is the config-page property bound to the switch; the
picker's `enabled` and the hint visibility derive from it. The page keeps its
`signal configurationChanged()` and `saveConfig()` forwarding from the existing
implementation; the switch is a standard `cfg_` property persisted by the dialog
automatically (no extra saveConfig logic needed for the bool).

### Files

- `config/main.xml`: add `<entry name="pimEventsEnabled" type="Bool"><default>true</default></entry>`.
- `ui/configCalendars.qml`: add the switch (`cfg_pimEventsEnabled`), gate the
  picker `enabled` on it, add the off-state hint, expand the not-installed
  placeholder with install guidance.
- `ui/EventsBackend.qml`: add `property bool pluginEnabled` (default true);
  gate `enablePimPlugin()` on it; on `onPluginEnabledChanged`, enable+collect or
  disable+clear as above.
- `ui/main.qml`: bind `pluginEnabled: Plasmoid.configuration.pimEventsEnabled`
  on the `EventsBackend` instance.

## Feature 2: Settings cog in the popup footer

In `ui/FullRepresentation.qml`, add a settings button to the footer
`RowLayout` (currently holding only "Open Merkuro"), placed to the **left** of
"Open Merkuro":

- `PlasmaComponents.Button` with `icon.name: "configure"`, an accessible
  text/tooltip "Configure Next Up Calendar".
- `onClicked: Plasmoid.internalAction("configure").trigger()` — the standard API
  a plasmoid uses to open its own config dialog (opens at the General page).
- Requires adding `import org.kde.plasma.plasmoid` to the file.

The "Open Merkuro" button stays right-aligned; the cog sits before it. No
behavior of the agenda list/placeholder changes.

## Data flow (Feature 1)

User opens Configure → Calendars → toggles "Show calendar events" → on Apply,
`pimEventsEnabled` persists → `EventsBackend` reacts: enabled→re-enable plugin
and re-collect; disabled→clear events → panel/popup update. When the plugin is
absent, the integration cannot be enabled (nothing to enable); the page shows
install guidance.

## Error handling

- Plugin not installed: install-guidance placeholder; `EventsBackend` leaves
  `pimAvailable` false and never enables anything.
- Toggle off with no events: the existing empty-state placeholder is shown
  (intentionally generic "No upcoming events", not a distinct "turned off"
  message — kept simple).
- `Plasmoid.internalAction("configure")` returning null (unexpected): guard the
  cog `onClicked` so a missing action is a no-op rather than an error.

## Testing

No new pure-JS logic — `eventlogic.js` and its 28 Node tests are untouched
(`node --test` is a regression check only). Verification is visual + behavioral
via the QML harness and `plasmoidviewer`, with screenshots:

1. Installed + toggle on: switch on, picker interactive, shared-set note shown.
2. Installed + toggle off: picker greyed/disabled, hint shown.
3. Not installed (simulated): install-guidance placeholder, no toggle.
4. `EventsBackend` respects the switch: with the seeded viewer calendars,
   `pimEventsEnabled=false` collects 0 events; `=true` collects the events.
5. Cog button: present in the footer left of "Open Merkuro"; clicking triggers
   the configure action (verify the action resolves; full dialog-open is a
   manual/best-effort check).
6. General page and panel/popup rendering unaffected.

## Out of scope

A distinct "events turned off" popup message; per-calendar independent selection;
landing the cog directly on the Calendars config page; non-PIM calendar plugins.
