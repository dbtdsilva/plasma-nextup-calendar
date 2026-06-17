/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: compactRoot

    // { text: string, status: "ongoing" | "soon" | "clear" } — computed in main.qml
    required property var panelModel
    // current popup state, captured at press time for reliable click-to-close
    required property bool isExpanded

    signal activated(bool wasExpanded)

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // red = on a meeting, orange = starting soon, green = all clear
    readonly property color statusColor: {
        switch (compactRoot.panelModel.status) {
        case "ongoing": return Kirigami.Theme.negativeTextColor;
        case "soon": return Kirigami.Theme.neutralTextColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    // horizontal panel: claim the row's width; vertical panel: claim its height
    // and let the panel's thickness bound the width (label elides)
    Layout.preferredWidth: vertical ? -1 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: vertical ? 0 : Layout.preferredWidth
    Layout.preferredHeight: vertical ? label.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: compactRoot.statusColor
        }

        PlasmaComponents.Label {
            id: label
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: compactRoot.panelModel.text
            color: Kirigami.Theme.textColor
        }
    }

    MouseArea {
        anchors.fill: parent
        // capture at press: the popup may auto-collapse on focus-out before
        // onClicked runs, which would otherwise re-open it immediately
        property bool wasExpanded: false
        onPressed: wasExpanded = compactRoot.isExpanded
        onClicked: compactRoot.activated(wasExpanded)
    }
}
