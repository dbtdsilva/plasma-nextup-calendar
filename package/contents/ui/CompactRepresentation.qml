import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: compactRoot

    // {text: string, urgent: bool} — computed in main.qml
    required property var panelModel

    signal activated()

    Layout.preferredWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: Layout.preferredWidth

    PlasmaComponents.Label {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: compactRoot.panelModel.text
        color: compactRoot.panelModel.urgent
            ? Kirigami.Theme.negativeTextColor
            : Kirigami.Theme.textColor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: compactRoot.activated()
    }
}
