# Next Up Calendar Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Plasma 6 panel widget showing the next Akonadi (Merkuro) calendar event as panel text with countdown, plus a 7-day agenda popup with click-to-join meeting links.

**Architecture:** Pure QML plasmoid. `EventsBackend.qml` reads events through `org.kde.plasma.workspace.calendar` (`EventPluginsManager` + `Calendar` + `DaysModel.eventsForDate`) with the `pimevents` plugin enabled programmatically. All decision logic lives in `package/contents/js/eventlogic.js` as pure functions, unit-tested under Node (the file carries a CommonJS export guard so the identical file loads in QML and Node).

**Tech Stack:** QML (Plasma 6.6, Kirigami, PlasmaComponents 3), plain JavaScript, Node 22 `node:test` runner, `kpackagetool6`/`plasmoidviewer` for install/preview.

**Spec:** `docs/superpowers/specs/2026-06-12-nextup-widget-design.md`

---

## Verified API facts (do not re-derive)

- QML module: `import org.kde.plasma.workspace.calendar as PlasmaCalendar` (version 2.0, present on target system at `/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/plasma/workspace/calendar/`).
- `PlasmaCalendar.EventPluginsManager` — property `enabledPlugins: QStringList`, method `populateEnabledPluginsList(pluginsList)`, property `model` (roles include `pluginId`, `checked`).
- `PlasmaCalendar.Calendar` — properties `days`, `weeks`, `firstDayOfWeek`, `today: QDateTime`, `displayedDate`, `daysModel`; methods `resetToToday()`, `updateData()`. Wire plugins with `daysModel.setPluginsManager(manager)` in `Component.onCompleted` (this is exactly what `MonthView.qml` does).
- `daysModel.eventsForDate(date)` returns a list of `EventDataDecorator` value objects with properties: `startDateTime`, `endDateTime`, `isAllDay`, `isMinor`, `title`, `description`, `eventColor`, `eventType`. **No UID, no location, no URL.**
- `daysModel` emits `agendaUpdated(QDate)` as plugins deliver data asynchronously.
- The PIM plugin is installed at `/usr/lib/x86_64-linux-gnu/qt6/plugins/plasmacalendarplugins/pimevents.so`; its plugin ID is the basename (`pimevents`), but the backend discovers the exact ID from the model rather than hardcoding it.
- The month grid covers 42 cells; `eventsForDate` only answers for dates inside the grid. Today+tomorrow is always covered (≥5 trailing cells). The 7-day popup window may lose 1–2 trailing days at month end — accepted v1 limitation, do not engineer around it.

## File structure

```
package/
  metadata.json                      # KPackage applet metadata
  contents/
    config/main.xml                  # config schema (KConfigXT)
    config/config.qml                # registers the General config page
    ui/main.qml                      # PlasmoidItem; owns refresh loop + panel model
    ui/CompactRepresentation.qml     # panel text (urgent coloring)
    ui/FullRepresentation.qml        # agenda popup, click-to-join, Merkuro launcher
    ui/EventsBackend.qml             # Akonadi via pimevents; emits plain JS events
    ui/configGeneral.qml             # settings form
    js/eventlogic.js                 # pure functions (the ONLY place with decision logic)
tests/
  eventlogic.test.js                 # node:test suite
install.sh                           # kpackagetool6 install/upgrade helper
README.md
.gitignore
```

`main.qml` is the only QML file that calls `eventlogic.js` selection/format functions; representations receive ready-made data via properties. `EventsBackend` knows nothing about formatting; logic functions know nothing about QML.

---

### Task 1: Scaffolding — metadata, stub plasmoid, gitignore

**Files:**
- Create: `package/metadata.json`
- Create: `package/contents/ui/main.qml` (stub, replaced in Task 8)
- Create: `.gitignore`

- [ ] **Step 1: Write `package/metadata.json`**

```json
{
    "KPackageStructure": "Plasma/Applet",
    "KPlugin": {
        "Authors": [
            {
                "Email": "diogo.silva@loxy.cloud",
                "Name": "Diogo Silva"
            }
        ],
        "Category": "Date and Time",
        "Description": "Shows your next calendar event in the panel, like GNOME's Next Up",
        "Icon": "view-calendar-upcoming",
        "Id": "com.github.dbtdsilva.nextupcalendar",
        "License": "GPL-2.0-or-later",
        "Name": "Next Up Calendar",
        "Version": "0.1.0",
        "Website": "https://github.com/dbtdsilva/plasma-nextup-calendar"
    },
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

- [ ] **Step 2: Write stub `package/contents/ui/main.qml`**

```qml
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents

PlasmoidItem {
    PlasmaComponents.Label {
        anchors.centerIn: parent
        text: "Next Up"
    }
}
```

- [ ] **Step 3: Write `.gitignore`**

```
*.plasmoid
node_modules/
```

- [ ] **Step 4: Verify the stub loads**

Run: `plasmoidviewer --applet ./package` (close the window after checking)
Expected: a window opens showing the text "Next Up", no QML errors on the terminal.

- [ ] **Step 5: Commit**

```bash
git add package .gitignore
git commit -m "feat: scaffold plasmoid package with stub applet"
```

---

### Task 2: Test harness + dedupe()

**Files:**
- Create: `package/contents/js/eventlogic.js`
- Create: `tests/eventlogic.test.js`

- [ ] **Step 1: Write the failing test**

`tests/eventlogic.test.js`:

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../package/contents/js/eventlogic.js");

// Shared fixture helpers — used by all suites in this file.
const NOW = new Date("2026-06-12T13:00:00");

function ev(overrides) {
    return Object.assign({
        title: "Standup",
        startDateTime: new Date("2026-06-12T14:30:00"),
        endDateTime: new Date("2026-06-12T15:00:00"),
        isAllDay: false,
        eventColor: "",
        description: "",
    }, overrides);
}

test("dedupe removes events with same title and start", () => {
    const a = ev({});
    const b = ev({}); // same title + start, e.g. multi-day event listed under two dates
    const c = ev({ title: "Other" });
    const out = L.dedupe([a, b, c]);
    assert.equal(out.length, 2);
    assert.deepEqual(out.map(e => e.title), ["Standup", "Other"]);
});

test("dedupe keeps same title at different times", () => {
    const a = ev({});
    const b = ev({ startDateTime: new Date("2026-06-13T14:30:00") });
    assert.equal(L.dedupe([a, b]).length, 2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test`
Expected: FAIL — `Cannot find module '../package/contents/js/eventlogic.js'`

- [ ] **Step 3: Write minimal implementation**

`package/contents/js/eventlogic.js`:

```js
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure decision logic for the Next Up Calendar widget.
    This file is imported by QML AND required by Node tests — keep it free
    of QML and Node APIs alike.
*/

function dedupe(events) {
    var seen = {};
    var out = [];
    for (var i = 0; i < events.length; i++) {
        var e = events[i];
        var key = e.title + "|" + e.startDateTime.getTime();
        if (seen[key]) {
            continue;
        }
        seen[key] = true;
        out.push(e);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { dedupe: dedupe };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: event dedupe logic with node test harness"
```

---

### Task 3: selectPanelEvent()

**Files:**
- Modify: `package/contents/js/eventlogic.js`
- Modify: `tests/eventlogic.test.js`

Selection rules (from spec): ongoing timed event (earliest end wins) > next upcoming timed event in window > all-day event in window (only when no timed pending) > none. Window per `lookahead` option: `"today"` = rest of today, `"todayTomorrow"` = through tomorrow, `"24h"` = rolling 24 hours.

- [ ] **Step 1: Write the failing tests** (append to `tests/eventlogic.test.js`)

```js
test("selectPanelEvent prefers ongoing event, earliest end first", () => {
    const ongoingLong = ev({ title: "Long", startDateTime: new Date("2026-06-12T12:00:00"), endDateTime: new Date("2026-06-12T16:00:00") });
    const ongoingShort = ev({ title: "Short", startDateTime: new Date("2026-06-12T12:30:00"), endDateTime: new Date("2026-06-12T13:30:00") });
    const upcoming = ev({ title: "Later" });
    const sel = L.selectPanelEvent([ongoingLong, upcoming, ongoingShort], NOW, { lookahead: "todayTomorrow" });
    assert.equal(sel.kind, "ongoing");
    assert.equal(sel.event.title, "Short");
});

test("selectPanelEvent picks earliest upcoming timed event", () => {
    const later = ev({ title: "Later", startDateTime: new Date("2026-06-12T16:00:00"), endDateTime: new Date("2026-06-12T17:00:00") });
    const sooner = ev({ title: "Sooner" });
    const sel = L.selectPanelEvent([later, sooner], NOW, { lookahead: "todayTomorrow" });
    assert.equal(sel.kind, "upcoming");
    assert.equal(sel.event.title, "Sooner");
});

test("selectPanelEvent: timed event outranks all-day", () => {
    const allday = ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") });
    const sel = L.selectPanelEvent([allday, ev({})], NOW, { lookahead: "todayTomorrow" });
    assert.equal(sel.kind, "upcoming");
});

test("selectPanelEvent falls back to all-day, then none", () => {
    const allday = ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") });
    assert.equal(L.selectPanelEvent([allday], NOW, { lookahead: "todayTomorrow" }).kind, "allday");
    assert.equal(L.selectPanelEvent([], NOW, { lookahead: "todayTomorrow" }).kind, "none");
});

test("selectPanelEvent lookahead 'today' excludes tomorrow", () => {
    const tomorrow = ev({ startDateTime: new Date("2026-06-13T09:00:00"), endDateTime: new Date("2026-06-13T09:30:00") });
    const alldayTomorrow = ev({ title: "Trip", isAllDay: true, startDateTime: new Date("2026-06-13T00:00:00"), endDateTime: new Date("2026-06-14T00:00:00") });
    assert.equal(L.selectPanelEvent([tomorrow, alldayTomorrow], NOW, { lookahead: "today" }).kind, "none");
    assert.equal(L.selectPanelEvent([tomorrow], NOW, { lookahead: "todayTomorrow" }).kind, "upcoming");
});

test("selectPanelEvent lookahead '24h' is a rolling window", () => {
    const tomorrowNoon = ev({ startDateTime: new Date("2026-06-13T12:00:00"), endDateTime: new Date("2026-06-13T12:30:00") });
    const tomorrowEvening = ev({ startDateTime: new Date("2026-06-13T18:00:00"), endDateTime: new Date("2026-06-13T18:30:00") });
    assert.equal(L.selectPanelEvent([tomorrowNoon], NOW, { lookahead: "24h" }).kind, "upcoming");
    assert.equal(L.selectPanelEvent([tomorrowEvening], NOW, { lookahead: "24h" }).kind, "none");
});

test("selectPanelEvent ignores finished events", () => {
    const done = ev({ startDateTime: new Date("2026-06-12T10:00:00"), endDateTime: new Date("2026-06-12T11:00:00") });
    assert.equal(L.selectPanelEvent([done], NOW, { lookahead: "todayTomorrow" }).kind, "none");
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `node --test`
Expected: FAIL — `L.selectPanelEvent is not a function` (dedupe tests still pass)

- [ ] **Step 3: Implement** (add to `eventlogic.js` above the export guard; extend exports)

```js
function startOfDay(d) {
    var out = new Date(d.getTime());
    out.setHours(0, 0, 0, 0);
    return out;
}

function addDays(d, n) {
    var out = new Date(d.getTime());
    out.setDate(out.getDate() + n);
    return out;
}

function isSameDay(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

function selectPanelEvent(events, now, opts) {
    var lookahead = (opts && opts.lookahead) || "todayTomorrow";
    var todayStart = startOfDay(now);
    var windowEnd;
    if (lookahead === "today") {
        windowEnd = addDays(todayStart, 1);
    } else if (lookahead === "24h") {
        windowEnd = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    } else {
        windowEnd = addDays(todayStart, 2);
    }

    var timed = events.filter(function (e) { return !e.isAllDay; });

    var ongoing = timed.filter(function (e) {
        return e.startDateTime <= now && e.endDateTime > now;
    }).sort(function (a, b) { return a.endDateTime - b.endDateTime; });
    if (ongoing.length) {
        return { kind: "ongoing", event: ongoing[0] };
    }

    var upcoming = timed.filter(function (e) {
        return e.startDateTime > now && e.startDateTime < windowEnd;
    }).sort(function (a, b) { return a.startDateTime - b.startDateTime; });
    if (upcoming.length) {
        return { kind: "upcoming", event: upcoming[0] };
    }

    var allDay = events.filter(function (e) {
        return e.isAllDay && e.endDateTime > now && e.startDateTime < windowEnd;
    }).sort(function (a, b) { return a.startDateTime - b.startDateTime; });
    if (allDay.length) {
        return { kind: "allday", event: allDay[0] };
    }

    return { kind: "none", event: null };
}
```

Exports become:

```js
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        dedupe: dedupe,
        selectPanelEvent: selectPanelEvent,
        startOfDay: startOfDay,
        addDays: addDays,
        isSameDay: isSameDay,
    };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: panel event selection with lookahead windows"
```

---

### Task 4: truncateTitle() + formatPanelText()

**Files:**
- Modify: `package/contents/js/eventlogic.js`
- Modify: `tests/eventlogic.test.js`

Format rules (from spec): ongoing → `Title · ends 15:30`; upcoming ≤60 min → `Title · in 12 min` (urgent flag at ≤ threshold); later today → `Title · 14:30`; tomorrow → `Title · tomorrow 09:00`; all-day today → `Title · all day`; all-day tomorrow → `Title · tomorrow`; none → placeholder. Returns `{ text, urgent }`. Time formatter is injected so QML can pass `Qt.formatTime` and tests stay deterministic.

- [ ] **Step 1: Write the failing tests** (append)

```js
const FMT = d => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
const OPTS = { maxTitleLength: 30, urgentThresholdMinutes: 5, placeholderText: "No upcoming events" };

test("formatPanelText: ongoing shows end time", () => {
    const sel = { kind: "ongoing", event: ev({ endDateTime: new Date("2026-06-12T15:00:00") }) };
    assert.deepEqual(L.formatPanelText(sel, NOW, OPTS, FMT), { text: "Standup · ends 15:00", urgent: false });
});

test("formatPanelText: imminent shows countdown, urgent at threshold", () => {
    const at1310 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:10:00") }) };
    assert.deepEqual(L.formatPanelText(at1310, NOW, OPTS, FMT), { text: "Standup · in 10 min", urgent: false });
    const at1304 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:04:00") }) };
    assert.deepEqual(L.formatPanelText(at1304, NOW, OPTS, FMT), { text: "Standup · in 4 min", urgent: true });
});

test("formatPanelText: later today shows start time, tomorrow says tomorrow", () => {
    const later = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T16:00:00") }) };
    assert.equal(L.formatPanelText(later, NOW, OPTS, FMT).text, "Standup · 16:00");
    const tomorrow = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-13T09:00:00") }) };
    assert.equal(L.formatPanelText(tomorrow, NOW, OPTS, FMT).text, "Standup · tomorrow 09:00");
});

test("formatPanelText: all-day variants and placeholder", () => {
    const today = { kind: "allday", event: ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") }) };
    assert.equal(L.formatPanelText(today, NOW, OPTS, FMT).text, "Holiday · all day");
    const tomorrow = { kind: "allday", event: ev({ title: "Trip", isAllDay: true, startDateTime: new Date("2026-06-13T00:00:00"), endDateTime: new Date("2026-06-14T00:00:00") }) };
    assert.equal(L.formatPanelText(tomorrow, NOW, OPTS, FMT).text, "Trip · tomorrow");
    assert.deepEqual(L.formatPanelText({ kind: "none", event: null }, NOW, OPTS, FMT), { text: "No upcoming events", urgent: false });
});

test("formatPanelText truncates long titles with ellipsis", () => {
    const sel = { kind: "upcoming", event: ev({ title: "A very long meeting title that never ends", startDateTime: new Date("2026-06-12T16:00:00") }) };
    const out = L.formatPanelText(sel, NOW, Object.assign({}, OPTS, { maxTitleLength: 10 }), FMT);
    assert.equal(out.text, "A very lo… · 16:00");
});

test("formatPanelText rounds sub-minute countdown up to 1", () => {
    const sel = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:00:30") }) };
    assert.equal(L.formatPanelText(sel, NOW, OPTS, FMT).text, "Standup · in 1 min");
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `node --test`
Expected: FAIL — `L.formatPanelText is not a function`

- [ ] **Step 3: Implement** (add to `eventlogic.js`; extend exports with `formatPanelText`, `truncateTitle`, `defaultTimeFormat`)

```js
function defaultTimeFormat(d) {
    function pad(n) { return n < 10 ? "0" + n : "" + n; }
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}

function truncateTitle(title, maxLen) {
    if (!title) {
        return "";
    }
    if (title.length <= maxLen) {
        return title;
    }
    return title.slice(0, maxLen - 1).replace(/\s+$/, "") + "…";
}

function formatPanelText(selection, now, opts, fmtTime) {
    fmtTime = fmtTime || defaultTimeFormat;
    var o = opts || {};
    var maxLen = o.maxTitleLength || 30;
    var urgentMin = (o.urgentThresholdMinutes === undefined) ? 5 : o.urgentThresholdMinutes;
    var placeholder = o.placeholderText || "No upcoming events";

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test`
Expected: PASS (15 tests)

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: panel text formatting with countdown and urgency"
```

---

### Task 5: groupByDay() + timeRangeText() + findMeetingUrl()

**Files:**
- Modify: `package/contents/js/eventlogic.js`
- Modify: `tests/eventlogic.test.js`

Popup helpers. `groupByDay`: one group per day with events, today's group includes still-running events that started earlier; later days only contain events that start that day (no multi-day duplication); all-day events sort first; labels "Today"/"Tomorrow"/injected weekday name. `findMeetingUrl`: Teams/Meet/Zoom URLs from event description (HTML-encoded `&amp;` decoded first).

- [ ] **Step 1: Write the failing tests** (append)

```js
test("groupByDay groups, labels and sorts (all-day first)", () => {
    const events = [
        ev({ title: "Afternoon", startDateTime: new Date("2026-06-12T16:00:00"), endDateTime: new Date("2026-06-12T17:00:00") }),
        ev({ title: "Holiday", isAllDay: true, startDateTime: new Date("2026-06-12T00:00:00"), endDateTime: new Date("2026-06-13T00:00:00") }),
        ev({ title: "MondayMeet", startDateTime: new Date("2026-06-15T09:00:00"), endDateTime: new Date("2026-06-15T10:00:00") }),
    ];
    const groups = L.groupByDay(events, NOW, { popupDays: 7 }, d => "Monday");
    assert.equal(groups.length, 2);
    assert.equal(groups[0].label, "Today");
    assert.deepEqual(groups[0].events.map(e => e.title), ["Holiday", "Afternoon"]);
    assert.equal(groups[1].label, "Monday");
});

test("groupByDay: ongoing multi-day event appears under Today only; finished events dropped", () => {
    const ongoing = ev({ title: "Offsite", startDateTime: new Date("2026-06-11T09:00:00"), endDateTime: new Date("2026-06-13T18:00:00") });
    const finished = ev({ title: "Done", startDateTime: new Date("2026-06-12T08:00:00"), endDateTime: new Date("2026-06-12T09:00:00") });
    const groups = L.groupByDay([ongoing, finished], NOW, { popupDays: 7 }, d => "X");
    assert.equal(groups.length, 1);
    assert.equal(groups[0].label, "Today");
    assert.deepEqual(groups[0].events.map(e => e.title), ["Offsite"]);
});

test("groupByDay respects popupDays window", () => {
    const nextWeek = ev({ startDateTime: new Date("2026-06-20T09:00:00"), endDateTime: new Date("2026-06-20T10:00:00") });
    assert.equal(L.groupByDay([nextWeek], NOW, { popupDays: 7 }, d => "X").length, 0);
});

test("timeRangeText renders range or All day", () => {
    assert.equal(L.timeRangeText(ev({}), FMT), "14:30–15:00");
    assert.equal(L.timeRangeText(ev({ isAllDay: true }), FMT), "All day");
});

test("findMeetingUrl finds Teams/Meet/Zoom, decodes &amp;, else null", () => {
    const teams = "Join here <https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x&amp;y=z>";
    assert.equal(L.findMeetingUrl(teams), "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x&y=z");
    assert.equal(L.findMeetingUrl("at https://meet.google.com/abc-defg-hij today"), "https://meet.google.com/abc-defg-hij");
    assert.equal(L.findMeetingUrl("https://company.zoom.us/j/123456?pwd=x"), "https://company.zoom.us/j/123456?pwd=x");
    assert.equal(L.findMeetingUrl("no links here"), null);
    assert.equal(L.findMeetingUrl(""), null);
    assert.equal(L.findMeetingUrl(null), null);
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `node --test`
Expected: FAIL — `L.groupByDay is not a function`

- [ ] **Step 3: Implement** (add to `eventlogic.js`; extend exports with `groupByDay`, `timeRangeText`, `findMeetingUrl`)

```js
function groupByDay(events, now, opts, weekdayName) {
    var popupDays = (opts && opts.popupDays) || 7;
    var todayStart = startOfDay(now);
    var groups = [];
    for (var i = 0; i < popupDays; i++) {
        var dayStart = addDays(todayStart, i);
        var dayEnd = addDays(dayStart, 1);
        var dayEvents = events.filter(function (e) {
            if (i === 0) {
                // today: anything still relevant now, including multi-day events
                return e.endDateTime > now && e.startDateTime < dayEnd;
            }
            // later days: only events that start on this day
            return e.startDateTime >= dayStart && e.startDateTime < dayEnd;
        });
        if (!dayEvents.length) {
            continue;
        }
        dayEvents.sort(function (a, b) {
            if (a.isAllDay !== b.isAllDay) {
                return a.isAllDay ? -1 : 1;
            }
            return a.startDateTime - b.startDateTime;
        });
        var label = i === 0 ? "Today" : (i === 1 ? "Tomorrow" : weekdayName(dayStart));
        groups.push({ key: dayStart.toDateString(), label: label, date: dayStart, events: dayEvents });
    }
    return groups;
}

function timeRangeText(evnt, fmtTime) {
    fmtTime = fmtTime || defaultTimeFormat;
    if (evnt.isAllDay) {
        return "All day";
    }
    return fmtTime(evnt.startDateTime) + "–" + fmtTime(evnt.endDateTime);
}

var MEETING_URL_PATTERNS = [
    /https:\/\/teams\.microsoft\.com\/l\/meetup-join\/[^\s<>"')\]]+/i,
    /https:\/\/meet\.google\.com\/[a-z0-9-]+/i,
    /https:\/\/[\w.-]*zoom\.us\/j\/[^\s<>"')\]]+/i,
];

function findMeetingUrl(text) {
    if (!text) {
        return null;
    }
    var decoded = text.replace(/&amp;/g, "&");
    for (var i = 0; i < MEETING_URL_PATTERNS.length; i++) {
        var m = decoded.match(MEETING_URL_PATTERNS[i]);
        if (m) {
            return m[0];
        }
    }
    return null;
}
```

NOTE for the closure over `i` inside `filter`: `var i` is captured by reference, but `filter` runs synchronously before `i` changes — this is safe. If the linter complains, hoist `var isToday = i === 0;` before the filter and use that.

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test`
Expected: PASS (20 tests)

- [ ] **Step 5: Commit**

```bash
git add package/contents/js/eventlogic.js tests/eventlogic.test.js
git commit -m "feat: agenda grouping, time ranges and meeting URL detection"
```

---

### Task 6: Configuration schema and settings UI

**Files:**
- Create: `package/contents/config/main.xml`
- Create: `package/contents/config/config.qml`
- Create: `package/contents/ui/configGeneral.qml`

- [ ] **Step 1: Write `package/contents/config/main.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0 http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile name=""/>
    <group name="General">
        <entry name="lookahead" type="String">
            <label>Window for the panel's next event: today, todayTomorrow or 24h</label>
            <default>todayTomorrow</default>
        </entry>
        <entry name="maxTitleLength" type="Int">
            <label>Maximum characters of the event title shown in the panel</label>
            <default>30</default>
        </entry>
        <entry name="urgentThresholdMinutes" type="Int">
            <label>Highlight the panel text when the event starts within this many minutes</label>
            <default>5</default>
        </entry>
        <entry name="placeholderText" type="String">
            <label>Panel text when there is no upcoming event</label>
            <default>No upcoming events</default>
        </entry>
        <entry name="popupDays" type="Int">
            <label>Number of days shown in the agenda popup</label>
            <default>7</default>
        </entry>
    </group>
</kcfg>
```

- [ ] **Step 2: Write `package/contents/config/config.qml`**

```qml
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "view-calendar-upcoming"
        source: "configGeneral.qml"
    }
}
```

- [ ] **Step 3: Write `package/contents/ui/configGeneral.qml`**

```qml
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

    QQC2.SpinBox {
        id: popupDays
        Kirigami.FormData.label: i18n("Days shown in popup:")
        from: 1
        to: 14
    }
}
```

- [ ] **Step 4: Verify the config dialog opens**

Run: `plasmoidviewer --applet ./package`, then click the wrench/configure button in the viewer (or right-click → Configure).
Expected: a "General" page with the five controls, no QML errors in the terminal.

- [ ] **Step 5: Commit**

```bash
git add package/contents/config package/contents/ui/configGeneral.qml
git commit -m "feat: configuration schema and settings page"
```

---

### Task 7: EventsBackend.qml — live Akonadi events

**Files:**
- Create: `package/contents/ui/EventsBackend.qml`
- Modify: `package/contents/ui/main.qml` (temporary debug wiring, finalized in Task 8)

- [ ] **Step 1: Write `package/contents/ui/EventsBackend.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later

    Reads events from Akonadi through Plasma's calendar framework
    (pimevents plugin) and exposes them as plain JS objects.
*/
import QtQuick
import QtQml
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import "../js/eventlogic.js" as Logic

Item {
    id: backend

    // days to collect, counted from today (panel needs 2, popup needs popupDays)
    property int daysAhead: 7
    // plain JS objects: {title, startDateTime, endDateTime, isAllDay, eventColor, description}
    property var upcomingEvents: []
    property bool pimAvailable: false
    property string lastDayStamp: new Date().toDateString()

    signal eventsChanged()

    visible: false

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    // Discover the pimevents plugin id from the model instead of hardcoding it.
    Instantiator {
        model: pluginsManager.model
        delegate: QtObject {
            required property string pluginId
            Component.onCompleted: {
                if (pluginId.indexOf("pimevents") !== -1) {
                    backend.pimAvailable = true;
                    pluginsManager.populateEnabledPluginsList([pluginId]);
                }
            }
        }
    }

    PlasmaCalendar.Calendar {
        id: calendar
        days: 7
        weeks: 6
        firstDayOfWeek: Qt.locale().firstDayOfWeek
        today: new Date()
        Component.onCompleted: daysModel.setPluginsManager(pluginsManager)
    }

    Connections {
        target: calendar.daysModel
        function onAgendaUpdated(updatedDate) {
            refreshDebounce.restart();
        }
    }

    // agendaUpdated fires once per day cell; coalesce the burst into one collect()
    Timer {
        id: refreshDebounce
        interval: 250
        onTriggered: backend.collect()
    }

    // day rollover: re-anchor the calendar grid and re-query
    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        onTriggered: {
            const stamp = new Date().toDateString();
            if (stamp !== backend.lastDayStamp) {
                backend.lastDayStamp = stamp;
                calendar.today = new Date();
                calendar.resetToToday();
                backend.collect();
            }
        }
    }

    function collect() {
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        let all = [];
        for (let i = 0; i < daysAhead; i++) {
            const day = new Date(todayStart);
            day.setDate(day.getDate() + i);
            const list = calendar.daysModel.eventsForDate(day);
            for (let j = 0; j < list.length; j++) {
                const ev = list[j];
                all.push({
                    title: ev.title,
                    startDateTime: ev.startDateTime,
                    endDateTime: ev.endDateTime,
                    isAllDay: ev.isAllDay,
                    eventColor: ev.eventColor ? String(ev.eventColor) : "",
                    description: ev.description || "",
                });
            }
        }
        upcomingEvents = Logic.dedupe(all);
        console.info("[nextup] collected", upcomingEvents.length, "events for", daysAhead, "days");
        eventsChanged();
    }
}
```

- [ ] **Step 2: Wire it into the stub `main.qml` for verification**

Replace `package/contents/ui/main.qml` with:

```qml
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents

PlasmoidItem {
    id: root

    EventsBackend {
        id: backend
        daysAhead: 7
        onEventsChanged: {
            for (const e of backend.upcomingEvents) {
                console.info("[nextup]", e.title, e.startDateTime, e.isAllDay ? "(all day)" : "");
            }
        }
    }

    PlasmaComponents.Label {
        anchors.centerIn: parent
        text: "events: " + backend.upcomingEvents.length + (backend.pimAvailable ? "" : " (pimevents MISSING)")
    }
}
```

- [ ] **Step 3: Verify against live Akonadi**

Run: `plasmoidviewer --applet ./package 2>&1 | grep nextup`
Expected: within a few seconds, `[nextup] collected N events` lines listing real events from the Office365 calendar synced by Merkuro (N > 0 if there are events in the coming 7 days — check against Merkuro). If N stays 0 with events visible in Merkuro: first check `akonadictl status`, then add `calendar.updateData()` at the end of the Instantiator delegate's `Component.onCompleted` as a forced initial load, re-test.
Expected NOT to see: `(pimevents MISSING)` in the viewer window.

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/EventsBackend.qml package/contents/ui/main.qml
git commit -m "feat: live Akonadi events via pimevents calendar plugin"
```

---

### Task 8: CompactRepresentation + final main.qml

**Files:**
- Create: `package/contents/ui/CompactRepresentation.qml`
- Modify: `package/contents/ui/main.qml` (final form)

- [ ] **Step 1: Write `package/contents/ui/CompactRepresentation.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: compactRoot

    // {text: string, urgent: bool} — computed in main.qml
    required property var panelModel

    signal activated()

    Layout.preferredWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: Layout.preferredWidth

    PlasmaComponents.Label {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: compactRoot.panelModel.text
        color: compactRoot.panelModel.urgent
            ? Kirigami.Theme.negativeTextColor
            : Kirigami.Theme.textColor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: compactRoot.activated()
    }
}
```

- [ ] **Step 2: Write the final `package/contents/ui/main.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.plasma.plasmoid
import "../js/eventlogic.js" as Logic

PlasmoidItem {
    id: root

    property var panelModel: ({ text: "…", urgent: false })

    preferredRepresentation: compactRepresentation
    toolTipMainText: panelModel.text
    toolTipSubText: i18n("Next Up Calendar")

    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        onEventsChanged: root.refresh()
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
        const selection = Logic.selectPanelEvent(backend.upcomingEvents, now, { lookahead: cfg.lookahead });
        root.panelModel = Logic.formatPanelText(selection, now, {
            maxTitleLength: cfg.maxTitleLength,
            urgentThresholdMinutes: cfg.urgentThresholdMinutes,
            placeholderText: cfg.placeholderText,
        }, d => Qt.formatTime(d));
    }

    compactRepresentation: CompactRepresentation {
        panelModel: root.panelModel
        onActivated: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
    }
}
```

NOTE: `FullRepresentation.qml` doesn't exist yet — create a minimal placeholder so this task is verifiable on its own:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    required property var events
    required property bool pimAvailable
    required property int popupDays
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24
    PlasmaComponents.Label { anchors.centerIn: parent; text: "agenda coming in Task 9" }
}
```

NOTE: if `Connections { target: Plasmoid.configuration }` prints a warning about the `valueChanged` signal not existing, delete that whole `Connections` block and bind instead by adding `onDaysAheadChanged: root.refresh()` to the `EventsBackend` instance — config changes are not hot-critical (the 30 s timer picks them up anyway).

- [ ] **Step 3: Verify in the viewer**

Run: `plasmoidviewer --applet ./package`
Expected: the compact view shows either the next real event (`Title · in N min` / `· 14:30` / `· tomorrow 09:00` per your actual calendar — cross-check with Merkuro) or the placeholder text. Clicking it expands to the Task-9 placeholder popup.

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui
git commit -m "feat: panel text representation with countdown and urgency color"
```

---

### Task 9: FullRepresentation — agenda popup

**Files:**
- Modify: `package/contents/ui/FullRepresentation.qml` (replace placeholder)

- [ ] **Step 1: Write the real `package/contents/ui/FullRepresentation.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import "../js/eventlogic.js" as Logic

PlasmaExtras.Representation {
    id: full

    required property var events
    required property bool pimAvailable
    required property int popupDays

    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    collapseMarginsHint: true

    onEventsChanged: rebuild()
    onPopupDaysChanged: rebuild()
    Component.onCompleted: rebuild()

    P5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    function openMerkuro() {
        executable.connectSource("merkuro-calendar");
    }

    function activateEvent(description) {
        const url = Logic.findMeetingUrl(description);
        if (url) {
            Qt.openUrlExternally(url);
        } else {
            openMerkuro();
        }
    }

    function rebuild() {
        agendaModel.clear();
        const now = new Date();
        const fmt = d => Qt.formatTime(d);
        const groups = Logic.groupByDay(events, now, { popupDays: popupDays },
            d => Qt.formatDate(d, "dddd"));
        for (const group of groups) {
            for (const ev of group.events) {
                agendaModel.append({
                    dayLabel: group.label,
                    title: ev.title,
                    timeText: Logic.timeRangeText(ev, fmt),
                    eventColor: ev.eventColor,
                    description: ev.description,
                    hasMeetingUrl: Logic.findMeetingUrl(ev.description) !== null,
                });
            }
        }
    }

    ListModel {
        id: agendaModel
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: !full.pimAvailable || agendaModel.count === 0
        iconName: "view-calendar-upcoming"
        text: full.pimAvailable
            ? i18n("No upcoming events")
            : i18n("PIM Events plugin not found")
        explanation: full.pimAvailable
            ? i18n("Make sure your calendars are synced in Merkuro and Akonadi is running.")
            : i18n("Install the kdepim-addons package, then re-add this widget.")
    }

    contentItem: ListView {
        id: agendaList
        visible: agendaModel.count > 0
        model: agendaModel
        clip: true
        section.property: "dayLabel"
        section.delegate: Kirigami.ListSectionHeader {
            required property string section
            width: agendaList.width
            text: section
        }
        delegate: PlasmaComponents.ItemDelegate {
            id: row

            required property string title
            required property string timeText
            required property string eventColor
            required property string description
            required property bool hasMeetingUrl

            width: agendaList.width
            onClicked: full.activateEvent(row.description)

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    color: row.eventColor !== "" ? row.eventColor : Kirigami.Theme.highlightColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: row.title
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: row.timeText
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }
                }

                Kirigami.Icon {
                    visible: row.hasMeetingUrl
                    source: "camera-video-symbolic"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaExtras.PlasmoidHeading.Position.Footer
        RowLayout {
            anchors.fill: parent
            PlasmaComponents.Button {
                Layout.alignment: Qt.AlignRight
                text: i18n("Open Merkuro")
                icon.name: "view-calendar"
                onClicked: full.openMerkuro()
            }
        }
    }
}
```

NOTE: if `PlasmaExtras.Representation`'s `contentItem`/`footer` assignment produces errors on this Plasma version, fall back to a plain `Item` root with the ListView anchored above a bottom-anchored button row — keep the same delegates and functions.

- [ ] **Step 2: Verify in the viewer**

Run: `plasmoidviewer --applet ./package`
Expected: expanding the compact view shows day headers ("Today", "Tomorrow", weekday names) with events matching Merkuro; events whose description contains a Teams link show a camera icon; clicking such an event opens the browser at the Teams URL; clicking one without a link launches Merkuro; "Open Merkuro" button works.

- [ ] **Step 3: Run the full JS test suite once more**

Run: `node --test`
Expected: PASS (20 tests)

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/FullRepresentation.qml
git commit -m "feat: agenda popup with day groups and click-to-join"
```

---

### Task 10: install.sh, README, real-panel verification

**Files:**
- Create: `install.sh`
- Create: `README.md`

- [ ] **Step 1: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Install or upgrade the Next Up Calendar widget for the current user.
set -euo pipefail
cd "$(dirname "$0")"

ID="com.github.dbtdsilva.nextupcalendar"

if kpackagetool6 -t Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet --upgrade package
else
    kpackagetool6 -t Plasma/Applet --install package
fi

echo
echo "Installed. Add it via panel right-click > Add Widgets > 'Next Up Calendar'."
echo "If an older version appears cached, restart plasmashell:"
echo "  systemctl --user restart plasma-plasmashell.service"
```

Then: `chmod +x install.sh`

- [ ] **Step 2: Write `README.md`**

```markdown
# Next Up Calendar — Plasma Widget

Shows your next calendar event as text in the Plasma panel — the Plasma
equivalent of GNOME's [Next Up](https://extensions.gnome.org/extension/5278/next-up/)
extension. Click it for a multi-day agenda popup; click a meeting to join
its Teams/Meet/Zoom call directly.

Events come from **Akonadi**, so anything synced by
[Merkuro](https://apps.kde.org/merkuro.calendar/) or KOrganizer works —
including Office365, Google and CalDAV accounts.

![panel example: "Standup · in 12 min"]

## Features

- Next event in the panel: `Standup · in 12 min`, `Standup · 14:30`,
  `Standup · tomorrow 09:00`, with an urgent color when it's about to start
- Ongoing events: `Standup · ends 15:30`
- All-day events when nothing timed is pending
- Agenda popup grouped by day (Today / Tomorrow / weekday)
- Click-to-join: detects Teams, Google Meet and Zoom links in the event
- Configurable lookahead, title length, urgency threshold, placeholder text
  and popup length

## Requirements

- Plasma 6
- `kdepim-addons` (provides the PIM Events calendar plugin)
- Akonadi with your calendars set up (easiest via Merkuro)

## Install

    ./install.sh

Then add **Next Up Calendar** to your panel via *Add Widgets*.

## Development

Logic is pure JavaScript with tests: `node --test`
Preview: `plasmoidviewer --applet ./package`

## License

GPL-2.0-or-later
```

- [ ] **Step 3: Run the installer and verify in a real panel**

Run: `./install.sh`
Expected: `Successfully installed ...` (or upgraded).

Then manually: right-click panel → Add Widgets → search "Next Up Calendar" → drag to panel.
Expected: panel shows next event text matching Merkuro; popup, click-to-join, settings dialog all work in the real panel. Check the panel still renders correctly in both a horizontal panel and with long/short event titles (placeholder vs long meeting names).

- [ ] **Step 4: Run full test suite, commit**

Run: `node --test`
Expected: PASS (20 tests)

```bash
git add install.sh README.md
git commit -m "feat: install script and README"
```

---

## Final verification (after all tasks)

1. `node --test` → all pass.
2. `plasmoidviewer --applet ./package` → no QML errors in terminal output.
3. Real panel: event text correct vs Merkuro, urgent color appears within threshold, popup matches Merkuro's agenda, Teams link opens browser, config changes apply.
4. `git log --oneline` → one commit per task, working tree clean.

Out of scope (per spec): notifications, per-calendar filtering, Plasma 5, KDE Store upload automation.
