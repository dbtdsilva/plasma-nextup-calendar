# Panel Meeting-Status Dot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a colored status dot before the panel text (red = on a meeting, orange = meeting close, green = all clear) and stop styling the event name red.

**Architecture:** Pure logic in `eventlogic.js` gains a `status` field on `formatPanelText`'s return (`"ongoing" | "soon" | "clear"`, replacing `urgent`); `CompactRepresentation.qml` renders a theme-colored `Rectangle` dot before the label (mapping `status` → `negative`/`neutral`/`positiveTextColor`, the same treatment the claudeusage widget uses) and the label reverts to the normal text color.

**Tech Stack:** Plasma 6 QML (QtQuick / Kirigami / QtQuick.Layouts), pure-JS logic tested with Node's `node:test`.

**Spec:** `docs/superpowers/specs/2026-06-17-status-dot-design.md`

**Conventions (repo memory):** Conventional Commits, linear history, repo-local author identity already configured. Do NOT add any Co-Authored-By / Claude / Anthropic / "Generated with" trailer to commits.

**Test command:** `node --test tests/eventlogic.test.js` (currently 37 tests; this change edits existing `formatPanelText` cases — the count stays 37).

---

## File Structure

- `package/contents/js/eventlogic.js` — `formatPanelText` returns `status` not `urgent`. (Task 1)
- `tests/eventlogic.test.js` — `formatPanelText` cases assert `status`. (Task 1)
- `package/contents/ui/CompactRepresentation.qml` — dot + label row; status→color; no red text. (Task 2)
- `package/contents/ui/main.qml` — `panelModel` default carries `status`. (Task 2)
- `package/contents/config/main.xml` + `package/contents/ui/configGeneral.qml` — reword the threshold (now drives the orange dot). (Task 3)

---

## Task 1: `formatPanelText` returns `status` instead of `urgent`

**Files:**
- Modify: `package/contents/js/eventlogic.js` (`formatPanelText`, lines 108-138)
- Test: `tests/eventlogic.test.js` (the `formatPanelText` cases)

- [ ] **Step 1: Update the failing tests**

In `tests/eventlogic.test.js`, replace these four tests with the versions below.

Replace:
```js
test("formatPanelText: ongoing shows end time", () => {
    const sel = { kind: "ongoing", event: ev({ endDateTime: new Date("2026-06-12T15:00:00") }) };
    assert.deepEqual(L.formatPanelText(sel, NOW, OPTS, FMT), { text: "Standup · ends 15:00", urgent: false });
});
```
with:
```js
test("formatPanelText: ongoing shows end time, status ongoing", () => {
    const sel = { kind: "ongoing", event: ev({ endDateTime: new Date("2026-06-12T15:00:00") }) };
    assert.deepEqual(L.formatPanelText(sel, NOW, OPTS, FMT), { text: "Standup · ends 15:00", status: "ongoing" });
});
```

Replace:
```js
test("formatPanelText: imminent shows countdown, urgent at threshold", () => {
    const at1310 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:10:00") }) };
    assert.deepEqual(L.formatPanelText(at1310, NOW, OPTS, FMT), { text: "Standup · in 10 min", urgent: false });
    const at1304 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:04:00") }) };
    assert.deepEqual(L.formatPanelText(at1304, NOW, OPTS, FMT), { text: "Standup · in 4 min", urgent: true });
});
```
with:
```js
test("formatPanelText: imminent shows countdown; soon within threshold", () => {
    const at1310 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:10:00") }) };
    assert.deepEqual(L.formatPanelText(at1310, NOW, OPTS, FMT), { text: "Standup · in 10 min", status: "clear" });
    const at1304 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:04:00") }) };
    assert.deepEqual(L.formatPanelText(at1304, NOW, OPTS, FMT), { text: "Standup · in 4 min", status: "soon" });
});
```

Replace:
```js
test("formatPanelText: all-day variants and placeholder", () => {
    const today = { kind: "allday", event: ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") }) };
    assert.equal(L.formatPanelText(today, NOW, OPTS, FMT).text, "Holiday · all day");
    const tomorrow = { kind: "allday", event: ev({ title: "Trip", isAllDay: true, startDateTime: new Date("2026-06-13T00:00:00"), endDateTime: new Date("2026-06-14T00:00:00") }) };
    assert.equal(L.formatPanelText(tomorrow, NOW, OPTS, FMT).text, "Trip · tomorrow");
    assert.deepEqual(L.formatPanelText({ kind: "none", event: null }, NOW, OPTS, FMT), { text: "No upcoming events", urgent: false });
});
```
with:
```js
test("formatPanelText: all-day variants and placeholder are status clear", () => {
    const today = { kind: "allday", event: ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") }) };
    assert.deepEqual(L.formatPanelText(today, NOW, OPTS, FMT), { text: "Holiday · all day", status: "clear" });
    const tomorrow = { kind: "allday", event: ev({ title: "Trip", isAllDay: true, startDateTime: new Date("2026-06-13T00:00:00"), endDateTime: new Date("2026-06-14T00:00:00") }) };
    assert.deepEqual(L.formatPanelText(tomorrow, NOW, OPTS, FMT), { text: "Trip · tomorrow", status: "clear" });
    assert.deepEqual(L.formatPanelText({ kind: "none", event: null }, NOW, OPTS, FMT), { text: "No upcoming events", status: "clear" });
});
```

Replace:
```js
test("formatPanelText: urgent at exactly the threshold", () => {
    const at1305 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:05:00") }) };
    assert.deepEqual(L.formatPanelText(at1305, NOW, OPTS, FMT), { text: "Standup · in 5 min", urgent: true });
});
```
with:
```js
test("formatPanelText: soon at exactly the threshold, clear one minute beyond", () => {
    const at1305 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:05:00") }) };
    assert.deepEqual(L.formatPanelText(at1305, NOW, OPTS, FMT), { text: "Standup · in 5 min", status: "soon" });
    const at1306 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:06:00") }) };
    assert.deepEqual(L.formatPanelText(at1306, NOW, OPTS, FMT), { text: "Standup · in 6 min", status: "clear" });
});
```

(The other `formatPanelText` tests assert only `.text` and stay as-is — `text` is unchanged.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/eventlogic.test.js`
Expected: FAIL — the four edited tests fail because the implementation still returns `{ ..., urgent }` while the tests now expect `{ ..., status }` (deepEqual mismatch).

- [ ] **Step 3: Update `formatPanelText` to return `status`**

In `package/contents/js/eventlogic.js`, replace the body from the placeholder return through the final return (lines 116-137):

```js
    if (!selection || selection.kind === "none") {
        return { text: placeholder, urgent: false };
    }
    var evnt = selection.event;
    var title = truncateTitle(evnt.title, maxLen);

    if (selection.kind === "ongoing") {
        return { text: title + " · ends " + fmtTime(evnt.endDateTime), urgent: false };
    }
    if (selection.kind === "allday") {
        var suffix = (evnt.startDateTime <= now || isSameDay(evnt.startDateTime, now)) ? " · all day" : " · tomorrow";
        return { text: title + suffix, urgent: false };
    }
    // upcoming
    var mins = Math.ceil((evnt.startDateTime - now) / 60000);
    if (mins <= 60) {
        return { text: title + " · in " + mins + " min", urgent: mins <= urgentMin };
    }
    if (isSameDay(evnt.startDateTime, now)) {
        return { text: title + " · " + fmtTime(evnt.startDateTime), urgent: false };
    }
    return { text: title + " · tomorrow " + fmtTime(evnt.startDateTime), urgent: false };
```

with:

```js
    if (!selection || selection.kind === "none") {
        return { text: placeholder, status: "clear" };
    }
    var evnt = selection.event;
    var title = truncateTitle(evnt.title, maxLen);

    if (selection.kind === "ongoing") {
        return { text: title + " · ends " + fmtTime(evnt.endDateTime), status: "ongoing" };
    }
    if (selection.kind === "allday") {
        var suffix = (evnt.startDateTime <= now || isSameDay(evnt.startDateTime, now)) ? " · all day" : " · tomorrow";
        return { text: title + suffix, status: "clear" };
    }
    // upcoming
    var mins = Math.ceil((evnt.startDateTime - now) / 60000);
    if (mins <= 60) {
        return { text: title + " · in " + mins + " min", status: mins <= urgentMin ? "soon" : "clear" };
    }
    if (isSameDay(evnt.startDateTime, now)) {
        return { text: title + " · " + fmtTime(evnt.startDateTime), status: "clear" };
    }
    return { text: title + " · tomorrow " + fmtTime(evnt.startDateTime), status: "clear" };
```

(The comment on the `placeholder` line and the lines above it are unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: formatPanelText returns a status instead of urgent"
```

---

## Task 2: Status dot in the panel, no red text

**Files:**
- Modify: `package/contents/ui/CompactRepresentation.qml` (whole file)
- Modify: `package/contents/ui/main.qml` (`panelModel` default, line 13)

- [ ] **Step 1: Rewrite `CompactRepresentation.qml`**

Overwrite `package/contents/ui/CompactRepresentation.qml` with:

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: compactRoot

    // { text: string, status: "ongoing" | "soon" | "clear" } — computed in main.qml
    required property var panelModel
    // current popup state, captured at press time for reliable click-to-close
    required property bool isExpanded

    signal activated(bool wasExpanded)

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // red = on a meeting, orange = starting soon, green = all clear
    readonly property color statusColor: {
        switch (compactRoot.panelModel.status) {
        case "ongoing": return Kirigami.Theme.negativeTextColor;
        case "soon": return Kirigami.Theme.neutralTextColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    // horizontal panel: claim the row's width; vertical panel: claim its height
    // and let the panel's thickness bound the width (label elides)
    Layout.preferredWidth: vertical ? -1 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: vertical ? 0 : Layout.preferredWidth
    Layout.preferredHeight: vertical ? label.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: compactRoot.statusColor
        }

        PlasmaComponents.Label {
            id: label
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: compactRoot.panelModel.text
            color: Kirigami.Theme.textColor
        }
    }

    MouseArea {
        anchors.fill: parent
        // capture at press: the popup may auto-collapse on focus-out before
        // onClicked runs, which would otherwise re-open it immediately
        property bool wasExpanded: false
        onPressed: wasExpanded = compactRoot.isExpanded
        onClicked: compactRoot.activated(wasExpanded)
    }
}
```

- [ ] **Step 2: Update the `panelModel` default in `main.qml`**

In `package/contents/ui/main.qml`, replace line 13:

```qml
    property var panelModel: ({ text: "…", urgent: false })
```

with:

```qml
    property var panelModel: ({ text: "…", status: "clear" })
```

(The `refresh()` function is unchanged — it assigns `formatPanelText`'s return, which now carries `status`.)

- [ ] **Step 3: Confirm the JS suite is still green**

Run: `node --test tests/eventlogic.test.js`
Expected: PASS — 37 tests pass (no logic changed in this task).

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/CompactRepresentation.qml package/contents/ui/main.qml
git commit -m "feat: panel status dot replaces red urgent text"
```

---

## Task 3: Reword the threshold config (drives the orange dot)

**Files:**
- Modify: `package/contents/config/main.xml` (`urgentThresholdMinutes` `<label>`, line 20)
- Modify: `package/contents/ui/configGeneral.qml` (`urgentThreshold` SpinBox `FormData.label`, line 49)

- [ ] **Step 1: Reword the kcfg label**

In `package/contents/config/main.xml`, replace:

```xml
            <label>Highlight the panel text when the event starts within this many minutes</label>
```
with:
```xml
            <label>Minutes-before threshold that turns the panel status dot orange</label>
```

- [ ] **Step 2: Reword the config-page label**

In `package/contents/ui/configGeneral.qml`, replace:

```qml
        Kirigami.FormData.label: i18n("Highlight when starting within (minutes):")
```
with:
```qml
        Kirigami.FormData.label: i18n("Turn the status dot orange within (minutes):")
```

- [ ] **Step 3: Verify XML is well-formed and JS still green**

Run:
```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml'); print('XML OK')"
node --test tests/eventlogic.test.js 2>&1 | grep -E "# tests|# pass|# fail"
```
Expected: `XML OK`, then `# tests 37 / # pass 37 / # fail 0`.

- [ ] **Step 4: Commit**

```bash
git add package/contents/config/main.xml package/contents/ui/configGeneral.qml
git commit -m "docs: reword urgent threshold to describe the status dot"
```

---

## Verification (after all tasks)

Automated:
- [ ] `node --test tests/eventlogic.test.js` → 37 pass / 0 fail.
- [ ] `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('package/contents/config/main.xml')"` → OK.
- [ ] On push, the CI `validate` job runs `qmllint` (in the `ubuntu:26.04` container) over `CompactRepresentation.qml` — confirms the new QML is syntactically/structurally sound. Watch with `gh run watch`.

Visual (maintainer, on a Plasma session):
- [ ] `./install.sh` then `systemctl --user restart plasma-plasmashell.service`.
- [ ] Panel shows a dot before the text: **green** when the next event is far off / all-day / none, **orange** when it's within the threshold minutes, **red** while a meeting is ongoing. The event name is the normal text color (never red).
- [ ] General config page: the threshold control reads "Turn the status dot orange within (minutes):".

---

## Self-Review Notes

- **Spec coverage:** `status` field with ongoing/soon/clear mapping ✓ (T1); dot rendering with theme `negative`/`neutral`/`positiveTextColor` + red text removed ✓ (T2); `panelModel` carries `status` ✓ (T2); threshold reused for "soon" ✓ (T1, `mins <= urgentMin`); config reworded ✓ (T3); tests assert `status` incl. boundary ✓ (T1); panel-only scope (popup untouched) ✓. No icon asset added ✓.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Name/value consistency:** status values `"ongoing"`/`"soon"`/`"clear"` identical across `formatPanelText`, the tests, `CompactRepresentation.qml`'s `statusColor` switch, and `main.qml`'s default; theme colors `negativeTextColor`/`neutralTextColor`/`positiveTextColor` match the claudeusage mapping in the spec.
