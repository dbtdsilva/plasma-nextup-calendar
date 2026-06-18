/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later

    Reads events from Akonadi through Plasma's calendar framework
    (pimevents plugin) and exposes them as plain JS objects.
*/
import QtQuick
import QtQml
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.plasma5support as P5Support
import "../js/eventlogic.js" as Logic

Item {
    id: backend

    // days to collect, counted from today (panel needs 2, popup needs popupDays)
    property int daysAhead: 7
    // plain JS objects: {title, startDateTime, endDateTime, isAllDay, eventColor, description}
    property var upcomingEvents: []
    property bool pimAvailable: false
    property string pimPluginId: ""
    // Whether the calendar-events integration is on (fed from config by main.qml).
    // Defaults false so we only ever ENABLE the shared pimevents plugin once the
    // real config value arrives — never enable-at-discovery and then unload when a
    // stored "false" resolves a moment later, which would destabilise the shared
    // calendar plugin and crash other consumers (the Digital Clock).
    property bool pluginEnabled: false
    // minutes between forced calendar syncs (fed from config); 0 = off
    property int refreshIntervalMinutes: 0
    // timestamp of the last successful collect() (a Date), shown in the popup
    property var lastRefresh
    property string lastDayStamp: new Date().toDateString()

    onDaysAheadChanged: refreshDebounce.restart()

    signal eventsChanged()

    visible: false

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    // Discover the pimevents plugin id from the model instead of hardcoding it.
    //
    // Two pitfalls (verified against plasma-workspace 6.6.4 sources):
    // 1. populateEnabledPluginsList() only sets the model's checked state and
    //    never loads plugins; assigning the enabledPlugins property is what
    //    calls setEnabledPlugins() and actually loads the .so.
    // 2. setEnabledPlugins() resets pluginsManager.model, which makes this
    //    Instantiator synchronously destroy and recreate its delegates. So the
    //    enable call must be guarded (pimAvailable) and deferred via
    //    Qt.callLater out of the delegate's own (about-to-die) context,
    //    otherwise it recurses until the JS stack overflows.
    Instantiator {
        model: pluginsManager.model
        delegate: QtObject {
            required property string pluginId
            Component.onCompleted: {
                if (!backend.pimAvailable && pluginId.indexOf("pimevents") !== -1) {
                    backend.pimAvailable = true;
                    backend.pimPluginId = pluginId;
                    if (backend.pluginEnabled) {
                        Qt.callLater(backend.enablePimPlugin);
                    }
                }
            }
        }
    }

    function enablePimPlugin() {
        if (!pluginEnabled || !pimAvailable) {
            return;
        }
        if (pluginsManager.enabledPlugins.indexOf(pimPluginId) !== -1) {
            return; // already loaded — avoid a redundant model reset
        }
        // Loads the plugin; DaysModel reacts to pluginsChanged with a queued
        // update() that queries the visible date range.
        pluginsManager.enabledPlugins = [pimPluginId];
        console.info("[nextup] enabled calendar plugin:", pimPluginId);
    }

    // React to the config switch flipping at runtime.
    //
    // Enable-at-startup is driven by whichever of {plugin discovery, the
    // pluginEnabled binding resolving to true} happens last: discovery calls
    // enablePimPlugin() only if pluginEnabled is already true, and this handler
    // calls it on a false->true flip after discovery. enablePimPlugin() is
    // idempotent, so both firing is harmless.
    onPluginEnabledChanged: {
        if (!pimAvailable) {
            return;
        }
        if (pluginEnabled) {
            enablePimPlugin();
            refreshDebounce.restart();
        } else {
            // Do NOT unload the plugin (pluginsManager.enabledPlugins = []):
            // it is shared process-wide with the Digital Clock, and unloading it
            // out from under another live consumer crashes libcalendarplugin.so.
            // The collect() guard already makes "off" authoritative at the display
            // layer, so we just stop showing events and leave the plugin loaded.
            upcomingEvents = [];
            console.info("[nextup] calendar events disabled");
            eventsChanged();
        }
    }

    PlasmaCalendar.Calendar {
        id: calendar
        days: 7
        // 8 weeks, not the usual 6: the grid is month-anchored with up to 7 leading
        // cells, so 6 weeks can leave as few as 4 trailing days — losing events from
        // the collection window at month end. 56 cells guarantee >= 18 trailing days.
        weeks: 8
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

    // agendaUpdated only fires for dates that have data, so with an empty
    // calendar nothing would ever trigger collect(); emit one initial pass.
    Timer {
        interval: 3000
        running: true
        onTriggered: refreshDebounce.restart()
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

    // Force a sync on an interval so server-side changes appear without a manual
    // sync. We replicate exactly what Merkuro's "Update Calendar" does — a
    // per-collection synchronizeCollection(<id>, false) on each enabled calendar —
    // which fetches that folder immediately. (A resource-wide synchronize() is
    // incremental and lags 2-3 cycles before EWS yields a fresh change — verified
    // via dbus-monitor: Merkuro calls synchronizeCollection, not synchronize.)
    // The enabled calendar collection ids come from the PIM Events plugin's own
    // config (~/.config/plasmashellrc); calendar resources are auto-discovered by
    // agent type; falls back to resource-wide synchronize() if no ids are found.
    // The sync makes Akonadi fetch; the existing agendaUpdated -> collect() path
    // then refreshes the UI.
    P5Support.DataSource {
        id: syncExecutable
        engine: "executable"
        // Stamp the refresh time when the sync command finishes, so the popup's
        // "Updated" reflects every refresh attempt (the cadence), not only data
        // changes (which arrive later via agendaUpdated -> collect()). Disconnect
        // so the same source can run again next interval.
        onNewData: sourceName => {
            backend.lastRefresh = new Date();
            disconnectSource(sourceName);
        }
    }

    readonly property string syncCommand: 'QDBUS=$(command -v qdbus6 || command -v qdbus); [ -n "$QDBUS" ] || exit 0; CALS=$(grep -A20 "PIMEventsPlugin" "$HOME/.config/plasmashellrc" 2>/dev/null | grep -m1 "^calendars=" | cut -d= -f2 | tr "," " "); for id in $("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstances); do t=$("$QDBUS" org.freedesktop.Akonadi.Control /AgentManager org.freedesktop.Akonadi.AgentManager.agentInstanceType "$id"); case "$t" in akonadi_ews_resource|akonadi_davgroupware_resource|akonadi_google_resource|akonadi_ical_resource|akonadi_icaldir_resource|akonadi_openxchange_resource|akonadi_kalarm_resource|akonadi_birthdays_resource) if [ -n "$CALS" ]; then for c in $CALS; do "$QDBUS" org.freedesktop.Akonadi.Resource."$id" / org.freedesktop.Akonadi.Resource.synchronizeCollection "$c" false; done; else "$QDBUS" org.freedesktop.Akonadi.Resource."$id" / org.freedesktop.Akonadi.Resource.synchronize; fi ;; esac; done; echo synced'

    function syncCalendars() {
        console.info("[nextup] forcing calendar sync");
        syncExecutable.connectSource(backend.syncCommand);
    }

    Timer {
        interval: Math.max(1, backend.refreshIntervalMinutes) * 60000
        running: backend.refreshIntervalMinutes > 0 && backend.pluginEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: backend.syncCalendars()
    }

    function collect() {
        if (!pluginEnabled) {
            if (upcomingEvents.length > 0) {
                upcomingEvents = [];
                eventsChanged();
            }
            return;
        }
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        let all = [];
        for (let i = 0; i < daysAhead; i++) {
            const day = new Date(todayStart);
            day.setDate(day.getDate() + i);
            const list = calendar.daysModel.eventsForDate(day) || [];
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
        lastRefresh = new Date();
        console.info("[nextup] collected", upcomingEvents.length, "events for", daysAhead, "days");
        eventsChanged();
    }
}
