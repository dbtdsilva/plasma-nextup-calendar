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

test("dedupe keeps the first occurrence of a duplicate", () => {
    const a = ev({ description: "first" });
    const b = ev({ description: "second" }); // same title + start
    const out = L.dedupe([a, b]);
    assert.equal(out.length, 1);
    assert.equal(out[0], a);
});

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
