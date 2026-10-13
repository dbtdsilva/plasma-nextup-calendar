# Periodic Calendar Refresh + Last-Refresh Readout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Periodically force a sync of the calendar Akonadi resource(s) so new server-side events appear on their own, show "Updated HH:MM" in the popup, and move the settings cog next to "Open Merkuro".

**Architecture:** A timer in `EventsBackend.qml` runs a `qdbus` loop (via the executable `P5Support.DataSource`) that auto-discovers calendar resources by type and calls `synchronize()`; the existing `agendaUpdated → collect()` path then updates the UI, and `collect()` stamps `lastRefresh`. `FullRepresentation.qml`'s footer gains the readout and the rearranged buttons.

**Tech Stack:** Plasma 6 QML (QtQuick / Kirigami / `org.kde.plasma.plasma5support`), Akonadi D-Bus via `qdbus6`.

**Spec:** `docs/superpowers/specs/2026-06-18-periodic-refresh-design.md`

## Global Constraints

- Plasma 6 / Qt6. No new C++/binary dependencies (the sync shells out via the existing executable `DataSource` pattern).
- Default interval **3** minutes, configurable, **0 = off**. Resources are auto-discovered by agent **type** (no stored resource id).
- Conventional Commits; repo-local author identity already configured; do NOT add any Co-Authored-By / Claude / Anthropic / "Generated with" trailer.
- No new pure-JS logic → the **37** Node tests (`node --test tests/eventlogic.test.js`) are unchanged and remain the regression gate. QML correctness is verified with `qmllint` in an `ubuntu:26.04` container (the command is in the Verification section) and on push by CI's `validate` job.

---

## Task 1: Config entry + config-page control

**Files:**
- Modify: `package/contents/config/main.xml` (add `refreshIntervalMinutes`)
- Modify: `package/contents/ui/configGeneral.qml` (alias + "Calendar refresh" section)

**Interfaces:**
- Produces: config key `refreshIntervalMinutes` (Int, default 3) and the `cfg_refreshIntervalMinutes` page alias.

- [ ] **Step 1: Add the kcfg entry**

In `package/contents/config/main.xml`, insert this entry immediately after the `alertEnabled` entry's closing `</entry>` (line 50) and before `</group>`:
```xml
        <entry name="refreshIntervalMinutes" type="Int">
            <label>Force a calendar sync this often (minutes); 0 disables it</label>
            <default>3</default>
        </entry>
```

- [ ] **Step 2: Add the config-page alias**

In `package/contents/ui/configGeneral.qml`, after the line
`property alias cfg_alertEnabled: alertEnabled.checked`, add:
```qml
    property alias cfg_refreshIntervalMinutes: refreshInterval.value
```

- [ ] **Step 3: Add the "Calendar refresh" section**

In `package/contents/ui/configGeneral.qml`, the file currently ends with the alert CheckBox then the closing `}`:
```qml
    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify when imminent:")
        text: i18n("Show a desktop notification")
    }
}
```
Replace that with (adds the section before the closing brace):
```qml
    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify when imminent:")
        text: i18n("Show a desktop notification")
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Calendar refresh")
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: refreshInterval
        Kirigami.FormData.label: i18n("Refresh calendars every (minutes), 0 = off:")
        from: 0
        to: 240
    }
}
```

- [ ] **Step 4: Verify**

Run:
```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('XML OK')"
node --test tests/eventlogic.test.js 2>&1 | grep -E "# tests|# pass|# fail"
```
Expected: `XML OK`; `# tests 37 / # pass 37 / # fail 0`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/config/main.xml package/contents/ui/configGeneral.qml
git commit -m "feat: refreshIntervalMinutes config for periodic calendar sync"
```

---

## Task 2: Periodic sync + last-refresh stamp in `EventsBackend`

**Files:**
- Modify: `package/contents/ui/EventsBackend.qml`
- Modify: `package/contents/ui/main.qml` (feed `refreshIntervalMinutes`)

**Interfaces:**
- Consumes: config `refreshIntervalMinutes` (Task 1), via `main.qml`.
- Produces: `EventsBackend` property `var lastRefresh` (a `Date`, set on each successful `collect()`; unset until the first read) — consumed by Task 3.

- [ ] **Step 1: Add the plasma5support import**

In `package/contents/ui/EventsBackend.qml`, after
`import org.kde.plasma.workspace.calendar as PlasmaCalendar` add:
```qml
import org.kde.plasma.plasma5support as P5Support
```

- [ ] **Step 2: Add the properties**

After the line `property bool pluginEnabled: false` add:
```qml
    // minutes between forced calendar syncs (fed from config); 0 = off
    property int refreshIntervalMinutes: 0
    // timestamp of the last successful collect() (a Date), shown in the popup
    property var lastRefresh
```

- [ ] **Step 3: Add the sync machinery**

In `package/contents/ui/EventsBackend.qml`, immediately before the `function collect() {` line, add:
```qml
    // Force a sync of the calendar Akonadi resource(s) on an interval — the same
    // thing Merkuro's "Update Calendar" does. New server-side events otherwise may
    // not reach Akonadi until a manual sync (e.g. a stale EWS push subscription).
    // The sync makes Akonadi fetch; the existing agendaUpdated -> collect() path
    // then refreshes the UI. Resources are auto-discovered by agent type.
    P5Support.DataSource {
        id: syncExecutable
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    readonly property string syncCommand: 'QDBUS=$(command -v qdbus6 || command -v qdbus); [ -n "$QDBUS" ] || exit 0; for id in $("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstances); do t=$("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstanceType "$id"); case "$t" in akonadi_ews_resource|akonadi_davgroupware_resource|akonadi_google_resource|akonadi_ical_resource|akonadi_icaldir_resource|akonadi_openxchange_resource|akonadi_kalarm_resource) "$QDBUS" org.freedesktop.Akonadi.Resource."$id" / org.freedesktop.Akonadi.Resource.synchronize ;; esac; done'

    function syncCalendars() {
        syncExecutable.connectSource(backend.syncCommand);
    }

    Timer {
        interval: Math.max(1, backend.refreshIntervalMinutes) * 60000
        running: backend.refreshIntervalMinutes > 0 && backend.pluginEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: backend.syncCalendars()
    }

```

- [ ] **Step 4: Stamp `lastRefresh` in `collect()`**

In `collect()`, the success path currently reads:
```qml
        upcomingEvents = Logic.dedupe(all);
        console.info("[nextup] collected", upcomingEvents.length, "events for", daysAhead, "days");
        eventsChanged();
```
Change it to:
```qml
        upcomingEvents = Logic.dedupe(all);
        lastRefresh = new Date();
        console.info("[nextup] collected", upcomingEvents.length, "events for", daysAhead, "days");
        eventsChanged();
```
(The early-return disabled path is unchanged, so `lastRefresh` is only set when events are actually read.)

- [ ] **Step 5: Feed the interval from `main.qml`**

In `package/contents/ui/main.qml`, the `EventsBackend` block reads:
```qml
    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        pluginEnabled: Plasmoid.configuration.pimEventsEnabled
        onEventsChanged: root.refresh()
    }
```
Change it to:
```qml
    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        pluginEnabled: Plasmoid.configuration.pimEventsEnabled
        refreshIntervalMinutes: Plasmoid.configuration.refreshIntervalMinutes
        onEventsChanged: root.refresh()
    }
```

- [ ] **Step 6: Verify the sync command is valid and targets only calendars**

Run the exact `syncCommand` through a shell (it's benign — same as Merkuro's "Update Calendar"; triggers a real fetch). First a dry list, then the real thing:
```bash
QDBUS=$(command -v qdbus6 || command -v qdbus); [ -n "$QDBUS" ] || echo "no qdbus"
for id in $("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstances); do t=$("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstanceType "$id"); case "$t" in akonadi_ews_resource|akonadi_davgroupware_resource|akonadi_google_resource|akonadi_ical_resource|akonadi_icaldir_resource|akonadi_openxchange_resource|akonadi_kalarm_resource) echo "would sync $id [$t]"; "$QDBUS" org.freedesktop.Akonadi.Resource."$id" / org.freedesktop.Akonadi.Resource.synchronize && echo "  synced" ;; esac; done
```
Expected: prints `would sync akonadi_ews_resource_0 [akonadi_ews_resource]` then `synced` (exit 0); no errors. Then confirm the JS suite: `node --test tests/eventlogic.test.js` → 37/37.

- [ ] **Step 7: Commit**

```bash
git add package/contents/ui/EventsBackend.qml package/contents/ui/main.qml
git commit -m "feat: periodically force a calendar resource sync"
```

---

## Task 3: Footer readout + rearrange in `FullRepresentation`

**Files:**
- Modify: `package/contents/ui/FullRepresentation.qml` (add `lastRefresh`, rework footer)
- Modify: `package/contents/ui/main.qml` (pass `lastRefresh`)

**Interfaces:**
- Consumes: `EventsBackend.lastRefresh` (Task 2), via `main.qml`.

- [ ] **Step 1: Add the `lastRefresh` property**

In `package/contents/ui/FullRepresentation.qml`, after
`required property bool hideAllDay` add:
```qml
    // Date of the last successful collect() (from EventsBackend); may be undefined
    required property var lastRefresh
```

- [ ] **Step 2: Rework the footer**

Replace the entire footer block:
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
with:
```qml
    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaExtras.PlasmoidHeading.Position.Footer
        RowLayout {
            anchors.fill: parent

            PlasmaComponents.Label {
                text: full.lastRefresh ? i18n("Updated %1", Qt.formatTime(full.lastRefresh)) : ""
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

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

            PlasmaComponents.Button {
                text: i18n("Open Merkuro")
                icon.name: "view-calendar"
                onClicked: full.openMerkuro()
            }
        }
    }
```
(The last-refresh label is now first; the configure cog moved to after the spacer, immediately left of "Open Merkuro".)

- [ ] **Step 3: Pass `lastRefresh` from `main.qml`**

In `package/contents/ui/main.qml`, the `fullRepresentation` block reads:
```qml
    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
        hideAllDay: Plasmoid.configuration.popupHideAllDay
    }
```
Change it to:
```qml
    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
        hideAllDay: Plasmoid.configuration.popupHideAllDay
        lastRefresh: backend.lastRefresh
    }
```

- [ ] **Step 4: Verify the JS suite is still green**

Run: `node --test tests/eventlogic.test.js` → 37/37 (no logic changed).

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/FullRepresentation.qml package/contents/ui/main.qml
git commit -m "feat: show last-refresh time and move the settings cog by Merkuro"
```

---

## Verification (after all tasks)

- [ ] `node --test tests/eventlogic.test.js` → 37/37.
- [ ] `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml')"` → OK.
- [ ] **qmllint the changed QML in a Plasma 6 container** (docker available; image cached):
  ```bash
  docker run --rm -v "$PWD":/src -w /src ubuntu:26.04 bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y --no-install-recommends qt6-declarative-dev-tools qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-org-kde-kirigami plasma-workspace >/dev/null 2>&1
    export PATH="/usr/lib/qt6/bin:$PATH"
    qmllint package/contents/ui/EventsBackend.qml package/contents/ui/FullRepresentation.qml package/contents/ui/configGeneral.qml package/contents/ui/main.qml; echo "qmllint exit: $?"'
  ```
  Expected: exit 0 (unqualified-access / Plasmoid-context warnings are fine; `plasma5support` may warn as an unresolved import in the container — acceptable, it resolves on the real system). A *syntax/structural* error is a problem.
- [ ] Visual (maintainer): `./install.sh && systemctl --user restart plasma-plasmashell.service`. Confirm: General config has a "Calendar refresh" → "Refresh calendars every (minutes), 0 = off" spinbox (default 3); the popup footer shows `Updated HH:MM` on the left and `[cog][Open Merkuro]` on the right; and an event created server-side appears within ~the interval **without** a manual "Update Calendar".

---

## Known runtime risk (flag, don't pre-fix)

The executable `DataSource` runs its source through a shell (the existing `openMerkuro()` relies on the `||` operator, confirming this). The `syncCommand` is a multi-statement `sh` script (`for`/`case`/`;`). Step 6 of Task 2 proves the script itself is valid sh and performs the sync. If the visual check shows the timer never syncs, the fallback is to wrap the body as `sh -c '…'`; note it in the PR rather than guessing further.

## Self-Review Notes

- **Spec coverage:** `refreshIntervalMinutes` config (default 3, 0=off) ✓ (T1); timer + executable DataSource + auto-discovery-by-type sync command ✓ (T2); data update via existing `collect()` path + `lastRefresh` stamp ✓ (T2); "Updated HH:MM" bottom-left ✓ (T3); cog moved next to Merkuro ✓ (T3); no new pure logic / 37 tests ✓; throttling/`0`-off/`pluginEnabled` gating ✓ (T2). Out-of-scope items (manual refresh button, per-resource selection, relative time) absent.
- **Placeholder scan:** none — concrete code/commands throughout.
- **Name/type consistency:** `refreshIntervalMinutes` (config ↔ `cfg_` alias ↔ `EventsBackend` prop ↔ `main.qml` binding); `lastRefresh` (`EventsBackend` var Date ↔ `main.qml` binding ↔ `FullRepresentation` required var ↔ footer `Qt.formatTime`); `syncCommand`/`syncCalendars`/`syncExecutable` consistent within `EventsBackend`.
