/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import "../js/eventlogic.js" as Logic

PlasmaExtras.Representation {
    id: full

    required property var events
    required property bool pimAvailable
    required property int popupDays

    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    collapseMarginsHint: true

    onEventsChanged: rebuild()
    onPopupDaysChanged: rebuild()
    Component.onCompleted: rebuild()

    P5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    function openMerkuro() {
        executable.connectSource("merkuro-calendar");
    }

    function activateEvent(description) {
        const url = Logic.findMeetingUrl(description);
        if (url) {
            Qt.openUrlExternally(url);
        } else {
            openMerkuro();
        }
    }

    function rebuild() {
        agendaModel.clear();
        const now = new Date();
        const fmt = d => Qt.formatTime(d);
        const groups = Logic.groupByDay(events, now, { popupDays: popupDays },
            d => Qt.formatDate(d, "dddd"));
        for (const group of groups) {
            for (const ev of group.events) {
                agendaModel.append({
                    dayLabel: group.label,
                    title: ev.title,
                    timeText: Logic.timeRangeText(ev, fmt),
                    eventColor: ev.eventColor,
                    description: ev.description,
                    hasMeetingUrl: Logic.findMeetingUrl(ev.description) !== null,
                });
            }
        }
    }

    ListModel {
        id: agendaModel
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: !full.pimAvailable || agendaModel.count === 0
        iconName: "view-calendar-upcoming"
        text: full.pimAvailable
            ? i18n("No upcoming events")
            : i18n("PIM Events plugin not found")
        explanation: full.pimAvailable
            ? i18n("Make sure your calendars are synced in Merkuro and Akonadi is running.")
            : i18n("Install the kdepim-addons package, then re-add this widget.")
    }

    contentItem: ListView {
        id: agendaList
        visible: agendaModel.count > 0
        model: agendaModel
        clip: true
        section.property: "dayLabel"
        section.delegate: Kirigami.ListSectionHeader {
            required property string section
            width: agendaList.width
            text: section
        }
        delegate: PlasmaComponents.ItemDelegate {
            id: row

            required property string title
            required property string timeText
            required property string eventColor
            required property string description
            required property bool hasMeetingUrl

            width: agendaList.width
            onClicked: full.activateEvent(row.description)

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    color: row.eventColor !== "" ? row.eventColor : Kirigami.Theme.highlightColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: row.title
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: row.timeText
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }
                }

                Kirigami.Icon {
                    visible: row.hasMeetingUrl
                    source: "camera-video-symbolic"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaExtras.PlasmoidHeading.Position.Footer
        RowLayout {
            anchors.fill: parent
            PlasmaComponents.Button {
                Layout.alignment: Qt.AlignRight
                text: i18n("Open Merkuro")
                icon.name: "view-calendar"
                onClicked: full.openMerkuro()
            }
        }
    }
}
