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
