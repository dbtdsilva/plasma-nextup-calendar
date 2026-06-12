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

    // {text: string, urgent: bool} — computed in main.qml
    required property var panelModel
    // current popup state, captured at press time for reliable click-to-close
    required property bool isExpanded

    signal activated(bool wasExpanded)

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // horizontal panel: claim the text's width; vertical panel: claim the
    // text's height and let the panel's thickness bound the width (elide)
    Layout.preferredWidth: vertical ? -1 : label.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: vertical ? 0 : Layout.preferredWidth
    Layout.preferredHeight: vertical ? label.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1

    PlasmaComponents.Label {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: compactRoot.panelModel.text
        color: compactRoot.panelModel.urgent
            ? Kirigami.Theme.negativeTextColor
            : Kirigami.Theme.textColor
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
