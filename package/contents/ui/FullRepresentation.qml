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
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import "../js/eventlogic.js" as Logic

PlasmaExtras.Representation {
    id: full

    required property var events
    required property bool pimAvailable
    required property int popupDays
    required property bool hideAllDay
    // Date of the last successful collect() (from EventsBackend); may be undefined
    required property var lastRefresh

    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    collapseMarginsHint: true

    onEventsChanged: rebuild()
    onPopupDaysChanged: rebuild()
    onHideAllDayChanged: rebuild()
    Component.onCompleted: rebuild()

    P5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    // Launch via the registered desktop file so it resolves regardless of
    // binary name or Flatpak packaging; fall back to the bare binary on
    // installs without kstart.
    function openMerkuro() {
        executable.connectSource("kstart --application org.kde.merkuro.calendar || merkuro-calendar");
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
        const groups = Logic.groupByDay(events, now, { popupDays: popupDays, hideAllDay: hideAllDay },
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

    // Both the list and the placeholder must live inside the laid-out
    // contentItem. A PlaceholderMessage placed as a stray child of
    // PlasmaExtras.Representation gets no geometry and never renders, so the
    // empty / no-calendars-enabled state would otherwise show a blank popup.
    contentItem: Item {
        ListView {
            id: agendaList
            anchors.fill: parent
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
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaExtras.PlasmoidHeading.Position.Footer
        RowLayout {
            anchors.fill: parent

            PlasmaComponents.Label {
                text: full.lastRefresh ? i18n("Updated %1", Qt.formatTime(full.lastRefresh, "hh:mm:ss")) : ""
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.Button {
                icon.name: "configure"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Configure Next Up Calendar")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
                onClicked: {
                    const action = Plasmoid.internalAction("configure");
                    if (action) {
                        action.trigger();
                    }
                }
            }

            PlasmaComponents.Button {
                text: i18n("Open Merkuro")
                icon.name: "view-calendar"
                onClicked: full.openMerkuro()
            }
        }
    }
}
