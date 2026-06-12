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

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        dedupe: dedupe,
        selectPanelEvent: selectPanelEvent,
        startOfDay: startOfDay,
        addDays: addDays,
        isSameDay: isSameDay,
    };
}
