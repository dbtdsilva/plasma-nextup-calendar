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
        // 24 real hours deliberately, not wall-clock: across a DST change this is 23/25 wall hours
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
    var cut = title.slice(0, maxLen - 1);
    var lastCode = cut.charCodeAt(cut.length - 1);
    if (lastCode >= 0xD800 && lastCode <= 0xDBFF) {
        cut = cut.slice(0, -1);
    }
    return cut.replace(/\s+$/, "") + "…";
}

function formatPanelText(selection, now, opts, fmtTime) {
    fmtTime = fmtTime || defaultTimeFormat;
    var o = opts || {};
    var maxLen = o.maxTitleLength || 30;
    var urgentMin = (o.urgentThresholdMinutes === undefined) ? 5 : o.urgentThresholdMinutes;
    // || on purpose: an empty placeholder would collapse the panel click target
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

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        dedupe: dedupe,
        selectPanelEvent: selectPanelEvent,
        startOfDay: startOfDay,
        addDays: addDays,
        isSameDay: isSameDay,
        formatPanelText: formatPanelText,
        truncateTitle: truncateTitle,
        defaultTimeFormat: defaultTimeFormat,
    };
}
