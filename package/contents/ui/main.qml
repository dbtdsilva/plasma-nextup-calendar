/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.notification
import "../js/eventlogic.js" as Logic

PlasmoidItem {
    id: root

    property var panelModel: ({ text: "…", status: "clear" })
    // key of the event we have already alerted for; resets on widget reload
    property string lastAlertedKey: ""

    preferredRepresentation: compactRepresentation
    toolTipMainText: panelModel.text
    toolTipSubText: i18n("Next Up Calendar")

    EventsBackend {
        id: backend
        daysAhead: Math.max(2, Plasmoid.configuration.popupDays)
        pluginEnabled: Plasmoid.configuration.pimEventsEnabled
        refreshIntervalMinutes: Plasmoid.configuration.refreshIntervalMinutes
        onEventsChanged: root.refresh()
    }

    Notification {
        id: eventAlert
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "view-calendar-upcoming"
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
        const selection = Logic.selectPanelEvent(backend.upcomingEvents, now, {
            lookahead: cfg.lookahead,
            hideAllDay: cfg.panelHideAllDay,
        });
        root.panelModel = Logic.formatPanelText(selection, now, {
            maxTitleLength: cfg.maxTitleLength,
            urgentThresholdMinutes: cfg.urgentThresholdMinutes,
            placeholderText: cfg.placeholderText,
        }, d => Qt.formatTime(d));

        const alert = Logic.evaluateAlert(selection, now, {
            alertEnabled: cfg.alertEnabled,
            urgentThresholdMinutes: cfg.urgentThresholdMinutes,
        }, root.lastAlertedKey);
        root.lastAlertedKey = alert.key;
        if (alert.fire) {
            root.fireAlert(selection.event, now);
        }
    }

    function fireAlert(evnt, now) {
        const mins = Math.ceil((evnt.startDateTime - now) / 60000);
        eventAlert.title = evnt.title;
        eventAlert.text = i18np("Starts in %1 minute", "Starts in %1 minutes", mins);
        eventAlert.sendEvent();
    }

    compactRepresentation: CompactRepresentation {
        panelModel: root.panelModel
        isExpanded: root.expanded
        bold: Plasmoid.configuration.panelBold
        onActivated: wasExpanded => root.expanded = !wasExpanded
    }

    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
        hideAllDay: Plasmoid.configuration.popupHideAllDay
    }
}
