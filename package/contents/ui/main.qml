import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents

PlasmoidItem {
    id: root

    EventsBackend {
        id: backend
        daysAhead: 7
        onEventsChanged: {
            for (const e of backend.upcomingEvents) {
                console.info("[nextup]", e.title, e.startDateTime, e.isAllDay ? "(all day)" : "");
            }
        }
    }

    PlasmaComponents.Label {
        anchors.centerIn: parent
        text: "events: " + backend.upcomingEvents.length + (backend.pimAvailable ? "" : " (pimevents MISSING)")
    }
}
