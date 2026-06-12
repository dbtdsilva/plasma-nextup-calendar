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
