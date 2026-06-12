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
        isExpanded: root.expanded
        onActivated: wasExpanded => root.expanded = !wasExpanded
    }

    fullRepresentation: FullRepresentation {
        events: backend.upcomingEvents
        pimAvailable: backend.pimAvailable
        popupDays: Plasmoid.configuration.popupDays
    }
}
