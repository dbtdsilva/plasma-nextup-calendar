# Panel/Popup Filters + Pre-event Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independent "hide all-day events" toggles for the panel and the agenda popup, plus an optional desktop notification that fires once X minutes before the next-up event.

**Architecture:** All decision logic stays pure in `js/eventlogic.js` (Node-tested): `selectPanelEvent`/`groupByDay` gain a `hideAllDay` option, and a new `evaluateAlert()` decides fire-once. QML (`main.qml`) holds the in-memory `lastAlertedKey` and calls `org.kde.notification`'s `sendEvent()`. Four new `cfg_` entries are surfaced in a regrouped config page.

**Tech Stack:** KDE Plasma 6 plasmoid (QML / Kirigami / QtQuick.Controls), pure-JS logic tested with Node's built-in `node:test`.

**Spec:** `docs/superpowers/specs/2026-06-16-filters-and-alert-design.md`

**Conventions (from repo memory):** Conventional Commits, linear history, author Diogo Silva <dbtdsilva@gmail.com> (repo-local git identity, already configured). Do NOT add any Co-Authored-By / Claude / Anthropic reference to commits.

**Full test suite command (run from repo root):** `node --test tests/eventlogic.test.js`

---

## File Structure

- `package/contents/js/eventlogic.js` — pure logic. Add `eventKey`, `hideAllDay` gates in `selectPanelEvent` and `groupByDay`, and `evaluateAlert`. (Tasks 1–4)
- `tests/eventlogic.test.js` — Node tests for every logic change. (Tasks 1–4)
- `package/contents/config/main.xml` — four new config entries. (Task 5)
- `package/contents/ui/configGeneral.qml` — regrouped form with the new controls. (Task 6)
- `package/contents/ui/main.qml` — pass `panelHideAllDay` to `selectPanelEvent`, evaluate + send the alert, pass `popupHideAllDay` down. (Task 7)
- `package/contents/ui/FullRepresentation.qml` — accept `hideAllDay`, pass to `groupByDay`. (Task 8)

Tasks 1–4 are pure logic with real unit tests (TDD). Tasks 5–8 are QML/config wiring that cannot be Node-tested; each ends by confirming the JS suite is still green, and the final Verification section covers visual/behavioral checks.

---

## Task 1: Extract `eventKey` helper (shared with `dedupe`)

A single key string `title + "|" + start-epoch` is needed by both `dedupe` (already builds it inline) and the new `evaluateAlert`. Extract it first so both reuse one definition.

**Files:**
- Modify: `package/contents/js/eventlogic.js:10-23` (`dedupe`) and `:193-207` (`module.exports`)
- Test: `tests/eventlogic.test.js`

- [ ] **Step 1: Write the failing test**

Add after the existing `dedupe` tests (after line 40, the `"dedupe keeps the first occurrence..."` test) in `tests/eventlogic.test.js`:

```js
test("eventKey combines title and start epoch", () => {
    const e = ev({ title: "Sync", startDateTime: new Date("2026-06-12T14:30:00") });
    assert.equal(L.eventKey(e), "Sync|" + new Date("2026-06-12T14:30:00").getTime());
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — `L.eventKey is not a function` (TypeError) in the new test; the other 28 tests still pass.

- [ ] **Step 3: Add `eventKey` and use it in `dedupe`**

In `package/contents/js/eventlogic.js`, replace the `dedupe` function (lines 10-23) with:

```js
function eventKey(e) {
    return e.title + "|" + e.startDateTime.getTime();
}

function dedupe(events) {
    var seen = {};
    var out = [];
    for (var i = 0; i < events.length; i++) {
        var e = events[i];
        var key = eventKey(e);
        if (seen[key]) {
            continue;
        }
        seen[key] = true;
        out.push(e);
    }
    return out;
}
```

Then add `eventKey` to the exports object (inside `module.exports = { ... }`, after the `dedupe: dedupe,` line):

```js
        dedupe: dedupe,
        eventKey: eventKey,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 29 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "refactor: extract eventKey helper shared with dedupe"
```

---

## Task 2: `hideAllDay` option in `selectPanelEvent`

When the panel should hide all-day events, skip the all-day fallback branch so the panel returns `none` instead of an all-day event. The ongoing/upcoming branches already only consider timed events, so this is the only change point.

**Files:**
- Modify: `package/contents/js/eventlogic.js:72-77` (the all-day fallback block in `selectPanelEvent`)
- Test: `tests/eventlogic.test.js`

- [ ] **Step 1: Write the failing tests**

Add after the existing `"selectPanelEvent falls back to all-day, then none"` test (after line 69) in `tests/eventlogic.test.js`:

```js
test("selectPanelEvent hideAllDay suppresses the all-day fallback", () => {
    const allday = ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") });
    assert.equal(L.selectPanelEvent([allday], NOW, { lookahead: "todayTomorrow", hideAllDay: true }).kind, "none");
    // without the flag the all-day fallback still works (regression guard)
    assert.equal(L.selectPanelEvent([allday], NOW, { lookahead: "todayTomorrow" }).kind, "allday");
});

test("selectPanelEvent hideAllDay still returns a timed upcoming event", () => {
    const allday = ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") });
    const timed = ev({ title: "Sync", startDateTime: new Date("2026-06-12T16:00:00"), endDateTime: new Date("2026-06-12T17:00:00") });
    const sel = L.selectPanelEvent([allday, timed], NOW, { lookahead: "todayTomorrow", hideAllDay: true });
    assert.equal(sel.kind, "upcoming");
    assert.equal(sel.event.title, "Sync");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — `selectPanelEvent hideAllDay suppresses the all-day fallback` fails: actual `kind` is `"allday"`, expected `"none"`.

- [ ] **Step 3: Gate the all-day fallback branch**

In `package/contents/js/eventlogic.js`, replace the all-day fallback block (lines 72-77):

```js
    var allDay = events.filter(function (e) {
        return e.isAllDay && e.endDateTime > now && e.startDateTime < windowEnd;
    }).sort(function (a, b) { return a.startDateTime - b.startDateTime; });
    if (allDay.length) {
        return { kind: "allday", event: allDay[0] };
    }
```

with:

```js
    if (!(opts && opts.hideAllDay)) {
        var allDay = events.filter(function (e) {
            return e.isAllDay && e.endDateTime > now && e.startDateTime < windowEnd;
        }).sort(function (a, b) { return a.startDateTime - b.startDateTime; });
        if (allDay.length) {
            return { kind: "allday", event: allDay[0] };
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 31 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: hideAllDay option for selectPanelEvent"
```

---

## Task 3: `hideAllDay` option in `groupByDay`

When the popup should hide all-day events, drop them before grouping. The existing empty-day `continue` then naturally omits any day that had only all-day events.

**Files:**
- Modify: `package/contents/js/eventlogic.js:134-137` (top of `groupByDay`)
- Test: `tests/eventlogic.test.js`

- [ ] **Step 1: Write the failing test**

Add after the existing `"groupByDay respects popupDays window"` test (after line 188) in `tests/eventlogic.test.js`:

```js
test("groupByDay hideAllDay drops all-day rows and empty days", () => {
    const events = [
        ev({ title: "Afternoon", startDateTime: new Date("2026-06-12T16:00:00"), endDateTime: new Date("2026-06-12T17:00:00") }),
        ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") }),
        ev({ title: "TripDay", isAllDay: true, startDateTime: new Date("2026-06-14T00:00:00"), endDateTime: new Date("2026-06-15T00:00:00") }),
    ];
    const groups = L.groupByDay(events, NOW, { popupDays: 7, hideAllDay: true }, d => "X");
    assert.equal(groups.length, 1);
    assert.equal(groups[0].label, "Today");
    assert.deepEqual(groups[0].events.map(e => e.title), ["Afternoon"]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — `groups.length` is `2` (Today with Holiday+Afternoon, plus the TripDay group), expected `1`.

- [ ] **Step 3: Filter all-day events at the top of `groupByDay`**

In `package/contents/js/eventlogic.js`, the function currently begins:

```js
function groupByDay(events, now, opts, weekdayName) {
    var popupDays = (opts && opts.popupDays) || 7;
    var todayStart = startOfDay(now);
```

Insert the filter so it reads:

```js
function groupByDay(events, now, opts, weekdayName) {
    var popupDays = (opts && opts.popupDays) || 7;
    if (opts && opts.hideAllDay) {
        events = events.filter(function (e) { return !e.isAllDay; });
    }
    var todayStart = startOfDay(now);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 32 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: hideAllDay option for groupByDay"
```

---

## Task 4: `evaluateAlert` pure decision function

Decide whether to fire a one-time alert for the next-up event. Side-effect-free; `main.qml` owns the `lastAlertedKey` state and the actual notification.

**Files:**
- Modify: `package/contents/js/eventlogic.js` (add function after `groupByDay`, ~line 163; add to `module.exports`)
- Test: `tests/eventlogic.test.js`

- [ ] **Step 1: Write the failing tests**

Add at the end of `tests/eventlogic.test.js` (after the last test, line 219):

```js
const ALERT_OPTS = { alertEnabled: true, alertMinutesBefore: 5 };

test("evaluateAlert: disabled never fires", () => {
    const sel = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:03:00") }) };
    assert.deepEqual(L.evaluateAlert(sel, NOW, { alertEnabled: false, alertMinutesBefore: 5 }, ""), { fire: false, key: "" });
});

test("evaluateAlert: fires once when upcoming within threshold", () => {
    const sel = { kind: "upcoming", event: ev({ title: "Sync", startDateTime: new Date("2026-06-12T13:03:00") }) };
    const out = L.evaluateAlert(sel, NOW, ALERT_OPTS, "");
    assert.equal(out.fire, true);
    assert.equal(out.key, L.eventKey(sel.event));
    // already alerted for this event -> no re-fire, key preserved
    const again = L.evaluateAlert(sel, NOW, ALERT_OPTS, out.key);
    assert.deepEqual(again, { fire: false, key: out.key });
});

test("evaluateAlert: does not fire beyond threshold", () => {
    const sel = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:10:00") }) };
    assert.deepEqual(L.evaluateAlert(sel, NOW, ALERT_OPTS, ""), { fire: false, key: "" });
});

test("evaluateAlert: non-upcoming selections never fire", () => {
    const ongoing = { kind: "ongoing", event: ev({ startDateTime: new Date("2026-06-12T12:00:00"), endDateTime: new Date("2026-06-12T14:00:00") }) };
    assert.equal(L.evaluateAlert(ongoing, NOW, ALERT_OPTS, "").fire, false);
    const allday = { kind: "allday", event: ev({ isAllDay: true }) };
    assert.equal(L.evaluateAlert(allday, NOW, ALERT_OPTS, "").fire, false);
    assert.equal(L.evaluateAlert({ kind: "none", event: null }, NOW, ALERT_OPTS, "").fire, false);
});

test("evaluateAlert: a new event after a previous alert fires for the new key", () => {
    const first = ev({ title: "First", startDateTime: new Date("2026-06-12T13:03:00") });
    const firstKey = L.eventKey(first);
    const second = { kind: "upcoming", event: ev({ title: "Second", startDateTime: new Date("2026-06-12T13:04:00") }) };
    const out = L.evaluateAlert(second, NOW, ALERT_OPTS, firstKey);
    assert.equal(out.fire, true);
    assert.equal(out.key, L.eventKey(second.event));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — `L.evaluateAlert is not a function` (TypeError) in the new tests.

- [ ] **Step 3: Implement `evaluateAlert`**

In `package/contents/js/eventlogic.js`, add this function immediately after `groupByDay` ends (after its closing `}` at line 163, before `function timeRangeText`):

```js
function evaluateAlert(selection, now, opts, lastAlertedKey) {
    var o = opts || {};
    if (!o.alertEnabled || !selection || selection.kind !== "upcoming") {
        return { fire: false, key: lastAlertedKey };
    }
    var key = eventKey(selection.event);
    if (key === lastAlertedKey) {
        return { fire: false, key: lastAlertedKey };
    }
    var mins = Math.ceil((selection.event.startDateTime - now) / 60000);
    if (mins <= o.alertMinutesBefore) {
        return { fire: true, key: key };
    }
    return { fire: false, key: lastAlertedKey };
}
```

Then add it to the exports object (inside `module.exports = { ... }`, after the `groupByDay: groupByDay,` line):

```js
        groupByDay: groupByDay,
        evaluateAlert: evaluateAlert,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: evaluateAlert pure decision for pre-event alert"
```

---

## Task 5: Config entries in `main.xml`

Add the four persisted settings. All default to a non-disruptive value so existing installs are unchanged.

**Files:**
- Modify: `package/contents/config/main.xml:31-34` (after the `pimEventsEnabled` entry, before `</group>`)

- [ ] **Step 1: Add the entries**

In `package/contents/config/main.xml`, insert these four entries immediately after the closing `</entry>` of `pimEventsEnabled` (line 34) and before `</group>` (line 35):

```xml
        <entry name="panelHideAllDay" type="Bool">
            <label>Hide all-day events in the panel</label>
            <default>false</default>
        </entry>
        <entry name="popupHideAllDay" type="Bool">
            <label>Hide all-day events in the agenda popup</label>
            <default>false</default>
        </entry>
        <entry name="alertEnabled" type="Bool">
            <label>Show a notification before the next event</label>
            <default>false</default>
        </entry>
        <entry name="alertMinutesBefore" type="Int">
            <label>Minutes before the next event to notify</label>
            <default>5</default>
        </entry>
```

- [ ] **Step 2: Verify the XML is well-formed**

Run: `python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse('package/contents/config/main.xml'); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Confirm the JS suite is still green**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass (config changes do not touch logic).

- [ ] **Step 4: Commit**

```bash
git add package/contents/config/main.xml
git commit -m "feat: config entries for all-day filters and alert"
```

---

## Task 6: Config UI — regroup `configGeneral.qml` with the new controls

Reorganize the form into **Next up (panel)**, **Agenda popup**, and **Alert** sections (via section separators) and add the three new controls. The alert spinbox greys out when the alert checkbox is off.

**Files:**
- Modify: `package/contents/ui/configGeneral.qml` (whole file)

- [ ] **Step 1: Replace the file contents**

Overwrite `package/contents/ui/configGeneral.qml` with:

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_lookahead
    property alias cfg_maxTitleLength: maxTitleLength.value
    property alias cfg_urgentThresholdMinutes: urgentThreshold.value
    property alias cfg_placeholderText: placeholderText.text
    property alias cfg_popupDays: popupDays.value
    property alias cfg_panelHideAllDay: panelHideAllDay.checked
    property alias cfg_popupHideAllDay: popupHideAllDay.checked
    property alias cfg_alertEnabled: alertEnabled.checked
    property alias cfg_alertMinutesBefore: alertMinutesBefore.value

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Next up (panel)")
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Show next event from:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Rest of today"), value: "today" },
            { text: i18n("Today and tomorrow"), value: "todayTomorrow" },
            { text: i18n("Next 24 hours"), value: "24h" },
        ]
        onActivated: page.cfg_lookahead = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_lookahead)
    }

    QQC2.SpinBox {
        id: maxTitleLength
        Kirigami.FormData.label: i18n("Maximum title length:")
        from: 10
        to: 100
    }

    QQC2.SpinBox {
        id: urgentThreshold
        Kirigami.FormData.label: i18n("Highlight when starting within (minutes):")
        from: 0
        to: 60
    }

    QQC2.TextField {
        id: placeholderText
        Kirigami.FormData.label: i18n("Text when no events:")
    }

    QQC2.CheckBox {
        id: panelHideAllDay
        Kirigami.FormData.label: i18n("Hide all-day events:")
        text: i18n("Don't show all-day events in the panel")
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Agenda popup")
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: popupDays
        Kirigami.FormData.label: i18n("Days shown in popup:")
        from: 1
        to: 14
    }

    QQC2.CheckBox {
        id: popupHideAllDay
        Kirigami.FormData.label: i18n("Hide all-day events:")
        text: i18n("Don't show all-day events in the agenda")
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Alert")
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify before the next event:")
        text: i18n("Show a desktop notification")
    }

    QQC2.SpinBox {
        id: alertMinutesBefore
        Kirigami.FormData.label: i18n("Minutes before:")
        from: 1
        to: 120
        enabled: alertEnabled.checked
    }
}
```

- [ ] **Step 2: Confirm the JS suite is still green**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass.

- [ ] **Step 3: Commit**

```bash
git add package/contents/ui/configGeneral.qml
git commit -m "feat: config UI sections for filters and alert"
```

---

## Task 7: Wire the panel filter and the notification in `main.qml`

Pass `panelHideAllDay` into `selectPanelEvent`, evaluate the alert each refresh, fire a desktop notification once when it flips, and pass `popupHideAllDay` to the popup.

**Files:**
- Modify: `package/contents/ui/main.qml` (whole file)

- [ ] **Step 1: Replace the file contents**

Overwrite `package/contents/ui/main.qml` with:

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.notification
import "../js/eventlogic.js" as Logic

PlasmoidItem {
    id: root

    property var panelModel: ({ text: "…", urgent: false })
    // key of the event we have already alerted for; resets on widget reload
    property string lastAlertedKey: ""

    preferredRepresentation: compactRepresentation
    toolTipMainText: panelModel.text
    toolTipSubText: i18n("Next Up Calendar")

    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        pluginEnabled: Plasmoid.configuration.pimEventsEnabled
        onEventsChanged: root.refresh()
    }

    Notification {
        id: eventAlert
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "view-calendar-upcoming"
    }

    // re-render countdowns even when no data changes
    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: Plasmoid.configuration
        function onValueChanged() { root.refresh() }
    }

    function refresh() {
        const now = new Date();
        const cfg = Plasmoid.configuration;
        const selection = Logic.selectPanelEvent(backend.upcomingEvents, now, {
            lookahead: cfg.lookahead,
            hideAllDay: cfg.panelHideAllDay,
        });
        root.panelModel = Logic.formatPanelText(selection, now, {
            maxTitleLength: cfg.maxTitleLength,
            urgentThresholdMinutes: cfg.urgentThresholdMinutes,
            placeholderText: cfg.placeholderText,
        }, d => Qt.formatTime(d));

        const alert = Logic.evaluateAlert(selection, now, {
            alertEnabled: cfg.alertEnabled,
            alertMinutesBefore: cfg.alertMinutesBefore,
        }, root.lastAlertedKey);
        root.lastAlertedKey = alert.key;
        if (alert.fire) {
            root.fireAlert(selection.event, now);
        }
    }

    function fireAlert(evnt, now) {
        const mins = Math.ceil((evnt.startDateTime - now) / 60000);
        eventAlert.title = evnt.title;
        eventAlert.text = i18np("Starts in %1 minute", "Starts in %1 minutes", mins);
        eventAlert.sendEvent();
    }

    compactRepresentation: CompactRepresentation {
        panelModel: root.panelModel
        isExpanded: root.expanded
        onActivated: wasExpanded => root.expanded = !wasExpanded
    }

    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
        hideAllDay: Plasmoid.configuration.popupHideAllDay
    }
}
```

- [ ] **Step 2: Confirm the JS suite is still green**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass (no logic touched).

- [ ] **Step 3: Commit**

```bash
git add package/contents/ui/main.qml
git commit -m "feat: wire panel all-day filter and pre-event notification"
```

---

## Task 8: Honor the popup all-day filter in `FullRepresentation.qml`

Accept the `hideAllDay` flag and pass it into `groupByDay`, rebuilding when it changes.

**Files:**
- Modify: `package/contents/ui/FullRepresentation.qml:18-29` (properties + rebuild triggers) and `:53-58` (`rebuild()` body)

- [ ] **Step 1: Add the `hideAllDay` property**

In `package/contents/ui/FullRepresentation.qml`, the required properties currently read:

```qml
    required property var events
    required property bool pimAvailable
    required property int popupDays
```

Change them to:

```qml
    required property var events
    required property bool pimAvailable
    required property int popupDays
    required property bool hideAllDay
```

- [ ] **Step 2: Rebuild when `hideAllDay` changes**

The rebuild triggers currently read:

```qml
    onEventsChanged: rebuild()
    onPopupDaysChanged: rebuild()
    Component.onCompleted: rebuild()
```

Change them to:

```qml
    onEventsChanged: rebuild()
    onPopupDaysChanged: rebuild()
    onHideAllDayChanged: rebuild()
    Component.onCompleted: rebuild()
```

- [ ] **Step 3: Pass `hideAllDay` into `groupByDay`**

In the `rebuild()` function, the `groupByDay` call currently reads:

```qml
        const groups = Logic.groupByDay(events, now, { popupDays: popupDays },
            d => Qt.formatDate(d, "dddd"));
```

Change it to:

```qml
        const groups = Logic.groupByDay(events, now, { popupDays: popupDays, hideAllDay: hideAllDay },
            d => Qt.formatDate(d, "dddd"));
```

- [ ] **Step 4: Confirm the JS suite is still green**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass.

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/FullRepresentation.qml
git commit -m "feat: honor popup all-day filter in agenda"
```

---

## Verification (after all tasks)

Automated:

- [ ] `node --test tests/eventlogic.test.js` → 37 tests pass, 0 fail.
- [ ] `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('OK')"` → `OK`.

Visual / behavioral (requires a Plasma session — use the `verify` or `run` skill, or the commands below):

- [ ] Install/upgrade the widget: `./install.sh` (restart plasmashell if a stale copy is cached: `systemctl --user restart plasma-plasmashell.service`). Quick standalone preview: `plasmoidviewer --applet ./package`.
- [ ] Config dialog (General page) shows three sections — **Next up (panel)**, **Agenda popup**, **Alert** — with the new "Hide all-day events" checkboxes and the alert checkbox + minutes spinbox. The minutes spinbox is greyed out until the alert checkbox is on.
- [ ] With **panel** "Hide all-day events" on and only an all-day event in the window, the panel shows the no-events placeholder (not "… · all day"); a timed event still shows normally.
- [ ] With **popup** "Hide all-day events" on, all-day rows disappear from the agenda and days containing only all-day events drop out; timed events remain.
- [ ] With the alert enabled and minutes set so the next-up event is inside the window, a desktop notification ("<title>" / "Starts in N minutes") appears once and does not repeat on subsequent refreshes; with the alert disabled, no notification fires.

---

## Self-Review Notes

- **Spec coverage:** hide-all-day panel (Tasks 2, 7) ✓; hide-all-day popup (Tasks 3, 8) ✓; separate toggles + config (Tasks 5, 6) ✓; alert decision (Task 4) + notification wiring (Task 7) ✓; `eventKey` reuse (Task 1) ✓; tests for all logic (Tasks 1–4) ✓. Dropped "confirmed" filter — intentionally not implemented (spec "Dropped from scope").
- **Type/name consistency:** `eventKey`, `evaluateAlert` (`{ fire, key }`), opts keys `hideAllDay` / `alertEnabled` / `alertMinutesBefore`, config keys `panelHideAllDay` / `popupHideAllDay` / `alertEnabled` / `alertMinutesBefore`, and `cfg_*` aliases all match across tasks and the `main.qml` call sites.
- **Test counts:** baseline 28 → +1 (Task 1) → +2 (Task 2) → +1 (Task 3) → +5 (Task 4) = 37.
