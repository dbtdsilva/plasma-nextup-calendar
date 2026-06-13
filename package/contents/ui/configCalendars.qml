/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Item {
    id: page

    // URL of pimevents' PimEventsConfig.qml, discovered from the plugin model
    property string pimConfigUi: ""

    PlasmaCalendar.EventPluginsManager {
        id: pluginsManager
    }

    // Find the pimevents row in the plugins model and read its configUi.
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

    Loader {
        id: pickerLoader
        anchors.fill: parent
        active: page.pimConfigUi !== ""
        source: page.pimConfigUi
    }
}
