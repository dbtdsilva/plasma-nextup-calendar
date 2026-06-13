# In-Widget Calendar Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Calendars" page to the widget's config dialog that hosts the `pimevents` plugin's own calendar picker, so the user can choose which Akonadi/Merkuro calendars the widget shows without leaving for the Digital Clock settings.

**Architecture:** A new `ConfigCategory` ("Calendars") whose page (`configCalendars.qml`) discovers the `pimevents` plugin's `configUi` URL from `EventPluginsManager.model` and loads that QML (`PimEventsConfig.qml`) in a `Loader`. The page forwards the picker's `configurationChanged` signal and `saveConfig()` to the dialog (the verified `ConfigurationContainmentAppearance` idiom), so Apply persists the selection to the shared `[PIMEventsPlugin]` config. No panel/popup or `eventlogic.js` changes.

**Tech Stack:** QML (Plasma 6.6, Kirigami, `org.kde.plasma.workspace.calendar`, hosting `org.kde.plasma.PimCalendars`/`kcmutils` via the loaded KCM). No new JS.

**Spec:** `docs/superpowers/specs/2026-06-13-calendar-picker-design.md`

---

## Verified facts (do not re-derive)

- `import org.kde.plasma.workspace.calendar as PlasmaCalendar` → `EventPluginsManager` has property `model` with roles `pluginId`, `checked`, `configUi`, `description`. The `pimevents` row's `configUi` is the URL of `…/plasmacalendarplugins/pimevents/PimEventsConfig.qml`.
- `PimEventsConfig.qml` is a `KCMUtils.ScrollViewKCM` exposing `signal configurationChanged` and `function saveConfig()`. Checking a box calls its internal `setChecked` and emits `configurationChanged`; `saveConfig()` persists to the shared `[PIMEventsPlugin] calendars=` config.
- The applet config dialog (`AppletConfiguration.qml`) connects to the **current page's** `configurationChanged` signal to enable Apply, and on Apply calls the current page's `saveConfig()`. Precedent: `ConfigurationContainmentAppearance.qml` (a `SimpleKCM` with `signal configurationChanged` and `saveConfig()` forwarding to a hosted child).
- All needed modules are installed: `org.kde.plasma.PimCalendars`, `org.kde.kcmutils`, `org.kde.kitemmodels`, `org.kde.kirigamiaddons.delegates`.
- The model lists plugins regardless of enabled state, so `configUi` is readable without enabling the plugin.
- Config dialog interactions (clicking checkboxes, Apply) cannot be driven headlessly. Verification uses (a) a standalone QML **harness Window** that loads `configCalendars.qml` and is screenshotted, and (b) `plasmoidviewer` log/error checks. The harness import path form that works on this system is `import "file:/abs/path/to/package/contents/ui" as W` (relative/absolute-without-scheme fail). Screenshots: `spectacle -a -b -n -o /tmp/x.png` after `sleep 5`; read the PNG to confirm pixels.

## File structure

```
package/contents/
  config/config.qml         # MODIFY: add second ConfigCategory "Calendars"
  ui/configCalendars.qml     # CREATE: hosts the pimevents picker
```

`configGeneral.qml`, `config/main.xml`, all of `ui/` except the new file, and `js/eventlogic.js` are untouched.

This feature is QML glue with no extractable pure logic, so it is verification-driven (render + behavior + no-errors) rather than unit-test-first. `node --test` is run only as a regression check that nothing in the JS layer changed.

---

### Task 1: Register the "Calendars" category and load the picker

**Files:**
- Modify: `package/contents/config/config.qml`
- Create: `package/contents/ui/configCalendars.qml`

- [ ] **Step 1: Add the category to `package/contents/config/config.qml`**

Replace the whole file with:

```qml
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "view-calendar-upcoming"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Calendars")
        icon: "office-calendar"
        source: "configCalendars.qml"
    }
}
```

- [ ] **Step 2: Create a minimal `package/contents/ui/configCalendars.qml` that discovers and loads the picker**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Item {
    id: page

    // URL of pimevents' PimEventsConfig.qml, discovered from the plugin model
    property string pimConfigUi: ""

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    // Find the pimevents row in the plugins model and read its configUi.
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

    Loader {
        id: pickerLoader
        anchors.fill: parent
        active: page.pimConfigUi !== ""
        source: page.pimConfigUi
    }
}
```

- [ ] **Step 3: Confirm the picker renders (harness screenshot)**

Write `/tmp/harness_cal.qml` (load the lowercase-named page by URL via a `Loader` — QML directory imports only expose uppercase-named files as types, so a `Loader` is required here):

```qml
import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 420; height: 520; x: 80; y: 80
    title: "nextup-calendars-test"
    Loader {
        anchors.fill: parent
        source: "file:/home/dsilva/Documents/plasma-nextup-calendar/package/contents/ui/configCalendars.qml"
    }
}
```

Run:
```bash
qml6 /tmp/harness_cal.qml >/tmp/harness_cal.log 2>&1 &
QPID=$!; sleep 6
spectacle -a -b -n -o /tmp/shot_cal.png >/dev/null 2>&1
sleep 1; kill $QPID 2>/dev/null
grep -iv "i18n\|installEventFilter" /tmp/harness_cal.log
```
Read `/tmp/shot_cal.png`.
Expected: a scrollable list of the user's Akonadi calendars, each with a checkbox (Office365 "Calendar", local, holidays, birthdays, etc.). No QML errors referencing `configCalendars.qml` in the log (KLocalizedString domain warnings are fine).
If the list is empty/blank: check the log for the `configUi` discovery — add a temporary `console.info("[nextup] pimConfigUi:", page.pimConfigUi)` in the Instantiator delegate, re-run, confirm it printed a non-empty `file://…/PimEventsConfig.qml`, then remove it. If `pimConfigUi` is empty, the model role name differs — STOP and report.

- [ ] **Step 4: Confirm the category loads in the real dialog without errors**

```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
timeout 12 plasmoidviewer --applet ./package 2>&1 | grep -i "error\|warn" | grep -iv isScreenUiReady | grep -i "configCalendars\|config.qml\|Calendars" || echo "(no package config errors)"
```
Expected: `(no package config errors)`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/config/config.qml package/contents/ui/configCalendars.qml
git commit -m "feat: add Calendars config page hosting the pimevents picker"
```

---

### Task 2: Wire Apply (configurationChanged + saveConfig) and add the shared-set note

**Files:**
- Modify: `package/contents/ui/configCalendars.qml`

- [ ] **Step 1: Replace `package/contents/ui/configCalendars.qml` with the wired version**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Item {
    id: page

    // Emitted to the config dialog so it enables the Apply button.
    signal configurationChanged()

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
            Layout.fillHeight: true
            active: page.pimConfigUi !== ""
            source: page.pimConfigUi
            // Forward the picker's change signal so Apply enables and persists.
            onItemChanged: {
                if (item && item.configurationChanged) {
                    item.configurationChanged.connect(page.configurationChanged);
                }
            }
        }
    }
}
```

- [ ] **Step 2: Confirm it still renders, with the note (harness screenshot)**

Re-run the Task 1 Step 3 harness commands (the `/tmp/harness_cal.qml` from Task 1 still applies). Read `/tmp/shot_cal.png`.
Expected: the same calendar checklist, now with an information banner at the top reading "This calendar selection is shared with other calendar widgets, such as the Digital Clock." No new QML errors.

- [ ] **Step 3: Confirm the save forwarding is sound (behavioral smoke test)**

This verifies our `saveConfig()` reaches the picker without error and writes the `[PIMEventsPlugin]` group. Use a throwaway config home so the real config is untouched:

```bash
cat > /tmp/harness_cal_save.qml <<'EOF'
import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 420; height: 520
    Loader {
        id: ldr; anchors.fill: parent
        source: "file:/home/dsilva/Documents/plasma-nextup-calendar/package/contents/ui/configCalendars.qml"
    }
    Timer {
        running: true; interval: 3000
        onTriggered: {
            if (ldr.item && ldr.item.saveConfig) { ldr.item.saveConfig(); }
            console.info("[nextup] saveConfig called");
        }
    }
}
EOF
rm -rf /tmp/nextup-cfgtest && mkdir -p /tmp/nextup-cfgtest
XDG_CONFIG_HOME=/tmp/nextup-cfgtest qml6 /tmp/harness_cal_save.qml >/tmp/harness_cal_save.log 2>&1 &
QPID=$!; sleep 6; kill $QPID 2>/dev/null
echo "=== saveConfig invoked & no error? ==="; grep -i "saveConfig called\|error\|TypeError" /tmp/harness_cal_save.log | grep -iv i18n
echo "=== a config file with [PIMEventsPlugin] was written? ==="; grep -rl "PIMEventsPlugin" /tmp/nextup-cfgtest 2>/dev/null || echo "(none written — see note)"
```
Expected: `[nextup] saveConfig called` present, no `TypeError`. A file under `/tmp/nextup-cfgtest` containing `[PIMEventsPlugin]` confirms persistence reaches disk. (If no file appears because the picker model wrote to the host rc before XDG override took effect, that is acceptable — the decisive checks are that `saveConfig()` ran without error and the picker rendered; note it in the report.)

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/configCalendars.qml
git commit -m "feat: persist calendar selection on Apply and note the shared set"
```

---

### Task 3: Missing-plugin fallback, and final regression

**Files:**
- Modify: `package/contents/ui/configCalendars.qml`

- [ ] **Step 1: Add a graceful fallback when no pimevents picker is available**

In `package/contents/ui/configCalendars.qml`, add this `Kirigami.PlaceholderMessage` as the last child inside the `ColumnLayout` (after the `Loader`):

```qml
        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
            visible: page.pimConfigUi === ""
            icon.name: "view-calendar-upcoming"
            text: i18n("Calendar selection unavailable")
            explanation: i18n("Install the kdepim-addons package to choose which calendars appear.")
        }
```

- [ ] **Step 2: Verify the fallback renders when the plugin is absent**

The plugin is installed on this system, so simulate absence by temporarily forcing the empty state: in `configCalendars.qml`, temporarily change the Instantiator's condition to `if (false && pluginId.indexOf("pimevents") !== -1 && configUi)`. Re-run the Task 1 Step 3 harness; read `/tmp/shot_cal.png`.
Expected: the calendar icon + "Calendar selection unavailable" + "Install the kdepim-addons package to choose which calendars appear." — not a blank area.
Then **revert** the temporary `false &&` edit and confirm with `git diff` that only the intended fallback block remains added.

- [ ] **Step 3: Confirm the picker still renders normally after reverting**

Re-run the Task 1 Step 3 harness once more; read `/tmp/shot_cal.png`.
Expected: the calendar checklist with the shared-set banner (the normal state), confirming the revert was clean.

- [ ] **Step 4: Regression — General page intact, JS untouched, package loads clean**

```bash
cd /home/dsilva/Documents/plasma-nextup-calendar
node --test 2>&1 | grep -E "^# (tests|pass|fail)"
git diff --stat HEAD -- package/contents/js package/contents/ui/configGeneral.qml package/contents/config/main.xml package/contents/ui/main.qml package/contents/ui/FullRepresentation.qml package/contents/ui/CompactRepresentation.qml package/contents/ui/EventsBackend.qml
timeout 12 plasmoidviewer --applet ./package 2>&1 | grep -i "error\|warn" | grep -iv isScreenUiReady | grep -i "package/contents" || echo "(no package errors)"
```
Expected: `# pass 28` / `# fail 0`; the `git diff --stat` prints **nothing** (those files unchanged); `(no package errors)`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/configCalendars.qml
git commit -m "feat: graceful fallback when kdepim-addons calendar picker is missing"
```

---

## Final verification (after all tasks)

1. Harness screenshot shows the calendar checklist + shared-set banner (normal), and the "Install kdepim-addons" placeholder (forced-empty) — both confirmed visually.
2. `saveConfig()` runs without error and reaches the picker.
3. `node --test` → 28/28; panel/popup/logic files unchanged (`git diff --stat` empty for them).
4. `plasmoidviewer` loads the package with no config-related QML errors.
5. Manual confirmation (best-effort, report if not automatable): in a real `plasmoidviewer` config dialog, the "Calendars" category appears beside "General", toggling a calendar enables Apply, and Apply changes `[PIMEventsPlugin] calendars=`.

## Out of scope

Per-widget independent selection (Option B); non-PIM calendar plugins; onboarding button from the popup; any panel/popup/logic change.
