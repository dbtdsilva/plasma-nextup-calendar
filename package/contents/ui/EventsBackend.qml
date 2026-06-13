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
    property string pimPluginId: ""
    // Whether the calendar-events integration is on (fed from config by main.qml).
    property bool pluginEnabled: true
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
        // Loads the plugin; DaysModel reacts to pluginsChanged with a queued
        // update() that queries the visible date range.
        pluginsManager.enabledPlugins = [pimPluginId];
        console.info("[nextup] enabled calendar plugin:", pimPluginId);
    }

    // React to the config switch flipping at runtime.
    onPluginEnabledChanged: {
        if (!pimAvailable) {
            return;
        }
        if (pluginEnabled) {
            enablePimPlugin();
            refreshDebounce.restart();
        } else {
            pluginsManager.enabledPlugins = [];
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
        console.info("[nextup] collected", upcomingEvents.length, "events for", daysAhead, "days");
        eventsChanged();
    }
}
