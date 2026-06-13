# PIM Events Toggle + Settings Cog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-widget "Show calendar events" switch (gating the calendar picker and the event integration) with install guidance, plus a settings cog button in the popup footer.

**Architecture:** A new `pimEventsEnabled` bool config entry (default true) becomes the single source of truth; `main.qml` feeds it into `EventsBackend` as `pluginEnabled`, which now enables the `pimevents` plugin only when on (and clears events when off). The Calendars config page gains a `QQC2.Switch` bound to `cfg_pimEventsEnabled`, gates the picker's `enabled` on it, and expands the not-installed placeholder with install help. `FullRepresentation`'s footer gains a cog button that triggers the widget's `configure` action.

**Tech Stack:** QML (Plasma 6.6, Kirigami, PlasmaComponents, QtQuick.Controls Switch), KConfigXT. No new JS.

**Spec:** `docs/superpowers/specs/2026-06-13-plugin-toggle-cog-design.md`

---

## Verified facts (do not re-derive)

- `AppletConfiguration.qml` auto-enables Apply when a config page's `cfg_<key>Changed` signal fires (it connects `currentItem["cfg_"+key+"Changed"]`). A `property alias cfg_pimEventsEnabled: enableSwitch.checked` emits `cfg_pimEventsEnabledChanged` automatically, so the switch needs no manual signal wiring.
- A plasmoid opens its own config dialog via `Plasmoid.internalAction("configure").trigger()` (requires `import org.kde.plasma.plasmoid`). It opens at the first/General page. Guard for null before calling `.trigger()`.
- `EventsBackend` runs inside a plasmoid context but does NOT import `org.kde.plasma.plasmoid`; keep it that way — `main.qml` owns `Plasmoid` and passes the value in via a property.
- Bare `qml6` harnesses don't read `plasmoidviewerrc`, so EventsBackend collects 0 there; behavioral collection tests must run under `plasmoidviewer` (which reads the seeded `~/.config/plasmoidviewerrc` `[PIMEventsPlugin] calendars=8,32,55,56,57`).
- Config-page QML files are lowercase-named → load them in harnesses by URL via a `Loader`, never via directory import.
- `qml6`, `plasmoidviewer`, `spectacle` available; Wayland; Akonadi running; kdepim-addons installed. `spectacle -a -b -n -o f.png` (active window) or `-f` (fullscreen) after `sleep ~6`; if `-a` grabs the wrong window, retry or use `-f`. Always VIEW the PNG with the Read tool — pixels are the verification.

## File map

- `package/contents/config/main.xml` — +`pimEventsEnabled` Bool (default true).
- `package/contents/ui/EventsBackend.qml` — +`pluginEnabled` property; gate enable; clear on disable.
- `package/contents/ui/main.qml` — bind `pluginEnabled` on the EventsBackend instance.
- `package/contents/ui/configCalendars.qml` — switch + picker gating + off-hint + richer install text.
- `package/contents/ui/FullRepresentation.qml` — footer cog button.

No pure-JS logic changes → `eventlogic.js`/tests untouched (`node --test` is a regression check only).

---

### Task 1: Config switch + EventsBackend respects it

**Files:**
- Modify: `package/contents/config/main.xml`
- Modify: `package/contents/ui/EventsBackend.qml`
- Modify: `package/contents/ui/main.qml`

- [ ] **Step 1: Add the config entry to `package/contents/config/main.xml`**

Inside `<group name="General">`, add this entry (e.g. after the `popupDays` entry, before `</group>`):

```xml
        <entry name="pimEventsEnabled" type="Bool">
            <label>Show calendar events from the PIM Events plugin</label>
            <default>true</default>
        </entry>
```

- [ ] **Step 2: Add `pluginEnabled` and gating to `package/contents/ui/EventsBackend.qml`**

Add the property next to the other top-level properties — insert after the `pimPluginId` line (currently line 21):

```qml
    // Whether the calendar-events integration is on (fed from config by main.qml).
    property bool pluginEnabled: true
```

Replace the discovery delegate's `Component.onCompleted` body (currently lines 49-55) so it records availability always but only enables when allowed:

```qml
            Component.onCompleted: {
                if (!backend.pimAvailable && pluginId.indexOf("pimevents") !== -1) {
                    backend.pimAvailable = true;
                    backend.pimPluginId = pluginId;
                    if (backend.pluginEnabled) {
                        Qt.callLater(backend.enablePimPlugin);
                    }
                }
            }
```

Replace `enablePimPlugin()` (currently lines 59-64) with a guarded version, and add a reactive handler. Use this block:

```qml
    function enablePimPlugin() {
        if (!pluginEnabled || !pimAvailable) {
            return;
        }
        // Loads the plugin; DaysModel reacts to pluginsChanged with a queued
        // update() that queries the visible date range.
        pluginsManager.enabledPlugins = [pimPluginId];
        console.info("[nextup] enabled calendar plugin:", pimPluginId);
    }

    // React to the config switch flipping at runtime.
    onPluginEnabledChanged: {
        if (!pimAvailable) {
            return;
        }
        if (pluginEnabled) {
            enablePimPlugin();
        } else {
            pluginsManager.enabledPlugins = [];
            upcomingEvents = [];
            console.info("[nextup] calendar events disabled");
            eventsChanged();
        }
    }
```

- [ ] **Step 3: Bind `pluginEnabled` in `package/contents/ui/main.qml`**

In the `EventsBackend { ... }` block (currently lines 18-22), add the binding so it reads:

```qml
    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        pluginEnabled: Plasmoid.configuration.pimEventsEnabled
        onEventsChanged: root.refresh()
    }
```

- [ ] **Step 4: Verify the ENABLED (default) path**

```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
timeout 20 plasmoidviewer --applet ./package 2>&1 | grep -i "nextup\|error" | grep -iv isScreenUiReady
```
Expected: `[nextup] enabled calendar plugin: pimevents` followed by `[nextup] collected N events for 7 days` with N > 0 (the seeded viewer calendars). No QML errors referencing package files.

- [ ] **Step 5: Verify the DISABLED path (throwaway)**

Temporarily force the switch off by editing `main.qml`'s binding to `pluginEnabled: false`, then:
```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
timeout 20 plasmoidviewer --applet ./package 2>&1 | grep -i "nextup\|error" | grep -iv isScreenUiReady
git checkout -- package/contents/ui/main.qml   # revert the throwaway
grep -n "pluginEnabled" package/contents/ui/main.qml   # confirm it's back to the config binding
```
Expected during the run: NO `[nextup] enabled calendar plugin` line, and `[nextup] collected 0 events for 7 days` (plugin never enabled → no events). This proves the guard. Confirm after revert that `main.qml` reads `pluginEnabled: Plasmoid.configuration.pimEventsEnabled` again.

- [ ] **Step 6: Commit**

```bash
git add package/contents/config/main.xml package/contents/ui/EventsBackend.qml package/contents/ui/main.qml
git commit -m "feat: gate calendar-events integration on a pimEventsEnabled switch"
```

---

### Task 2: Calendars page — switch, gating, install help

**Files:**
- Modify: `package/contents/ui/configCalendars.qml`

- [ ] **Step 1: Replace `package/contents/ui/configCalendars.qml` with the switch-gated version**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Item {
    id: page

    // Emitted to the config dialog so it enables the Apply button.
    signal configurationChanged()

    // Bound to the config entry by the dialog; drives the integration + gating.
    property alias cfg_pimEventsEnabled: enableSwitch.checked

    // URL of pimevents' PimEventsConfig.qml, discovered from the plugin model
    property string pimConfigUi: ""

    // Called by the config dialog on Apply (for the current page).
    function saveConfig() {
        if (pickerLoader.item && pickerLoader.item.saveConfig) {
            pickerLoader.item.saveConfig();
        }
    }

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    Instantiator {
        model: pluginsManager.model
        delegate: QtObject {
            required property string pluginId
            required property string configUi
            Component.onCompleted: {
                if (pluginId.indexOf("pimevents") !== -1 && configUi) {
                    page.pimConfigUi = configUi;
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        QQC2.Switch {
            id: enableSwitch
            Layout.fillWidth: true
            visible: page.pimConfigUi !== ""
            text: i18n("Show calendar events (PIM Events plugin)")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.pimConfigUi !== ""
            position: Kirigami.InlineMessage.Position.Header
            type: Kirigami.MessageType.Information
            text: i18n("This calendar selection is shared with other calendar widgets, such as the Digital Clock.")
        }

        Loader {
            id: pickerLoader
            Layout.fillWidth: true
            Layout.fillHeight: page.pimConfigUi !== ""
            active: page.pimConfigUi !== ""
            enabled: page.cfg_pimEventsEnabled
            source: page.pimConfigUi
            // Forward the picker's change signal so Apply enables and persists.
            onItemChanged: {
                if (item && item.configurationChanged) {
                    item.configurationChanged.connect(page.configurationChanged);
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.pimConfigUi !== "" && !page.cfg_pimEventsEnabled
            type: Kirigami.MessageType.Information
            text: i18n("Turn on “Show calendar events” to choose which calendars appear.")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignCenter
            visible: page.pimConfigUi === ""
            icon.name: "view-calendar-upcoming"
            text: i18n("Calendar selection unavailable")
            explanation: i18n("Calendar events require the PIM Events plugin from the kdepim-addons package. Install it with your distribution's package manager, then reopen settings.")
        }
    }
}
```

- [ ] **Step 2: Verify the three states (harness screenshots)**

Write `/tmp/h_cal_on.qml` (sets the switch ON, plugin present):
```qml
import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 440; height: 540; x: 90; y: 90; color: "#ffffff"
    title: "cal-on"
    Loader {
        id: ldr; anchors.fill: parent
        source: "file:/home/dsilva/Documents/plasma-nextup-calendar/package/contents/ui/configCalendars.qml"
        onItemChanged: if (item) item.cfg_pimEventsEnabled = true
    }
}
```
Run it, screenshot, VIEW:
```bash
qml6 /tmp/h_cal_on.qml >/tmp/h_cal_on.log 2>&1 &
P=$!; sleep 6; spectacle -a -b -n -o /tmp/shot_on.png >/dev/null 2>&1; sleep 1; kill $P 2>/dev/null
```
Expected (`/tmp/shot_on.png`): a Switch at top (ON), the shared-set banner, and the calendar checklist fully interactive (not dimmed).

Then `/tmp/h_cal_off.qml` — identical but `item.cfg_pimEventsEnabled = false`. Screenshot `/tmp/shot_off.png`, VIEW: the picker checklist is **dimmed/greyed** (disabled) and the "Turn on … to choose which calendars appear." hint is visible.

Then the not-installed state: temporarily change the Instantiator condition to `if (false && pluginId.indexOf("pimevents") !== -1 && configUi) {`, run `/tmp/h_cal_on.qml`, screenshot `/tmp/shot_absent.png`, VIEW: centered calendar icon + "Calendar selection unavailable" + the install-guidance explanation. **Revert** the `false &&` and confirm `git diff` shows only the intended new file content.

(Glyphs may not draw in bare qml6 — `i18n` undefined — but the Switch control, the dimmed-vs-interactive picker, and element presence are the proof. If `spectacle -a` grabs the wrong window, retry or use `-f`.)

- [ ] **Step 3: Confirm it loads clean in the real config dialog**

```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
timeout 12 plasmoidviewer --applet ./package 2>&1 | grep -i "error\|warn" | grep -iv isScreenUiReady | grep -i "configCalendars" || echo "(no configCalendars errors)"
node --test 2>&1 | grep -E "^# (pass|fail)"
```
Expected: `(no configCalendars errors)`; `# pass 28` / `# fail 0`.

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/configCalendars.qml
git commit -m "feat: calendar enable switch with picker gating and install help"
```

---

### Task 3: Settings cog in the popup footer

**Files:**
- Modify: `package/contents/ui/FullRepresentation.qml`

- [ ] **Step 1: Add the plasmoid + controls imports**

In `package/contents/ui/FullRepresentation.qml`, add these two imports to the existing import block (after `import org.kde.plasma.plasma5support as P5Support`):

```qml
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
```

- [ ] **Step 2: Replace the footer with a cog + Open Merkuro bar**

Replace the current footer block (the `footer: PlasmaExtras.PlasmoidHeading { ... }`, currently lines 155-166) with:

```qml
    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaExtras.PlasmoidHeading.Position.Footer
        RowLayout {
            anchors.fill: parent

            PlasmaComponents.Button {
                icon.name: "configure"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Configure Next Up Calendar")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
                onClicked: {
                    const action = Plasmoid.internalAction("configure");
                    if (action) {
                        action.trigger();
                    }
                }
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.Button {
                text: i18n("Open Merkuro")
                icon.name: "view-calendar"
                onClicked: full.openMerkuro()
            }
        }
    }
```

- [ ] **Step 3: Verify the footer renders with both buttons (forced full rep)**

Temporarily force the full representation so plasmoidviewer shows the popup, screenshot, then revert:
```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
sed -i 's/preferredRepresentation: compactRepresentation/preferredRepresentation: fullRepresentation/' package/contents/ui/main.qml
timeout 12 plasmoidviewer --applet ./package -s 380x520 >/tmp/cog.log 2>&1 &
P=$!; sleep 8; spectacle -a -b -n -o /tmp/shot_cog.png >/dev/null 2>&1; sleep 1; kill $P 2>/dev/null
git checkout -- package/contents/ui/main.qml
grep -i "error\|warn" /tmp/cog.log | grep -iv isScreenUiReady | grep -i "FullRepresentation\|package/contents" || echo "(no package errors)"
```
VIEW `/tmp/shot_cog.png`: the footer shows a cog (configure) icon button on the LEFT and the "Open Merkuro" button on the RIGHT. Expected: `(no package errors)`. (The real dialog-open on click is a manual/best-effort check — the null-guarded `internalAction("configure")` resolves in a real plasmoid; in a harness it would safely no-op.)

- [ ] **Step 4: Regression + commit**

```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
node --test 2>&1 | grep -E "^# (pass|fail)"
git diff --stat HEAD -- package/contents/js package/contents/ui/CompactRepresentation.qml
git add package/contents/ui/FullRepresentation.qml
git commit -m "feat: settings cog button in the agenda popup footer"
```
Expected: `# pass 28` / `# fail 0`; the `git diff --stat` prints nothing (those files untouched).

---

## Final verification (after all tasks)

1. Enabled path: `plasmoidviewer` logs the enable line + `collected N`. Disabled path (throwaway) logs no enable + `collected 0`. (Task 1)
2. Calendars page: switch-ON shows interactive picker; switch-OFF dims it + shows the hint; not-installed shows the install-guidance placeholder, centered. (Task 2 screenshots)
3. Footer shows the cog left of "Open Merkuro"; no package QML errors. (Task 3 screenshot)
4. `node --test` → 28/28; `eventlogic.js`, `CompactRepresentation.qml` untouched.
5. Manual/best-effort: in a real config dialog the switch persists and toggling it changes whether the panel shows events; the cog opens the settings dialog.

## Out of scope

A distinct "events turned off" popup message; per-calendar independent selection; landing the cog on the Calendars page; non-PIM calendar plugins.
