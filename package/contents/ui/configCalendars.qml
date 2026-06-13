/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Item {
    id: page

    // Emitted to the config dialog so it enables the Apply button.
    signal configurationChanged()

    // Bound to the config entry by the dialog; drives the integration + gating.
    property alias cfg_pimEventsEnabled: enableSwitch.checked

    // URL of pimevents' PimEventsConfig.qml, discovered from the plugin model
    property string pimConfigUi: ""

    // Called by the config dialog on Apply (for the current page).
    function saveConfig() {
        if (pickerLoader.item && pickerLoader.item.saveConfig) {
            pickerLoader.item.saveConfig();
        }
    }

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    Instantiator {
        model: pluginsManager.model
        delegate: QtObject {
            required property string pluginId
            required property string configUi
            Component.onCompleted: {
                if (pluginId.indexOf("pimevents") !== -1 && configUi) {
                    page.pimConfigUi = configUi;
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        QQC2.Switch {
            id: enableSwitch
            Layout.fillWidth: true
            visible: page.pimConfigUi !== ""
            text: i18n("Show calendar events (PIM Events plugin)")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.pimConfigUi !== ""
            position: Kirigami.InlineMessage.Position.Header
            type: Kirigami.MessageType.Information
            text: i18n("This calendar selection is shared with other calendar widgets, such as the Digital Clock.")
        }

        Loader {
            id: pickerLoader
            Layout.fillWidth: true
            Layout.fillHeight: page.pimConfigUi !== ""
            active: page.pimConfigUi !== ""
            enabled: page.cfg_pimEventsEnabled
            source: page.pimConfigUi
            // Forward the picker's change signal so Apply enables and persists.
            onItemChanged: {
                if (item && item.configurationChanged) {
                    item.configurationChanged.connect(page.configurationChanged);
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.pimConfigUi !== "" && !page.cfg_pimEventsEnabled
            type: Kirigami.MessageType.Information
            text: i18n("Turn on “Show calendar events” to choose which calendars appear.")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignCenter
            visible: page.pimConfigUi === ""
            icon.name: "view-calendar-upcoming"
            text: i18n("Calendar selection unavailable")
            explanation: i18n("Calendar events require the PIM Events plugin from the kdepim-addons package. Install it with your distribution's package manager, then reopen settings.")
        }
    }
}
