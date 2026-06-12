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

test("selectPanelEvent boundary: start exactly now is ongoing, end exactly now is finished", () => {
    const startsNow = ev({ startDateTime: new Date("2026-06-12T13:00:00"), endDateTime: new Date("2026-06-12T13:30:00") });
    assert.equal(L.selectPanelEvent([startsNow], NOW, { lookahead: "todayTomorrow" }).kind, "ongoing");
    const endsNow = ev({ startDateTime: new Date("2026-06-12T12:00:00"), endDateTime: new Date("2026-06-12T13:00:00") });
    assert.equal(L.selectPanelEvent([endsNow], NOW, { lookahead: "todayTomorrow" }).kind, "none");
});

test("selectPanelEvent boundary: start exactly at windowEnd is excluded", () => {
    const atMidnight = ev({ startDateTime: new Date("2026-06-13T00:00:00"), endDateTime: new Date("2026-06-13T00:30:00") });
    assert.equal(L.selectPanelEvent([atMidnight], NOW, { lookahead: "today" }).kind, "none");
    const at24h = ev({ startDateTime: new Date("2026-06-13T13:00:00"), endDateTime: new Date("2026-06-13T13:30:00") });
    assert.equal(L.selectPanelEvent([at24h], NOW, { lookahead: "24h" }).kind, "none");
});

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

test("formatPanelText: urgent at exactly the threshold", () => {
    const at1305 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T13:05:00") }) };
    assert.deepEqual(L.formatPanelText(at1305, NOW, OPTS, FMT), { text: "Standup · in 5 min", urgent: true });
});

test("formatPanelText: countdown at exactly 60 min, time form at 61", () => {
    const at60 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T14:00:00") }) };
    assert.equal(L.formatPanelText(at60, NOW, OPTS, FMT).text, "Standup · in 60 min");
    const at61 = { kind: "upcoming", event: ev({ startDateTime: new Date("2026-06-12T14:01:00") }) };
    assert.equal(L.formatPanelText(at61, NOW, OPTS, FMT).text, "Standup · 14:01");
});

test("truncateTitle never splits a surrogate pair", () => {
    const out = L.truncateTitle("AB\u{1F389}CD", 4);
    assert.equal(out, "AB…");
    assert.ok(!/[\uD800-\uDBFF]$/.test(out.slice(0, -1)));
});
