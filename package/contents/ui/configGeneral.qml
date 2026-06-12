import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_lookahead
    property alias cfg_maxTitleLength: maxTitleLength.value
    property alias cfg_urgentThresholdMinutes: urgentThreshold.value
    property alias cfg_placeholderText: placeholderText.text
    property alias cfg_popupDays: popupDays.value

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Show next event from:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Rest of today"), value: "today" },
            { text: i18n("Today and tomorrow"), value: "todayTomorrow" },
            { text: i18n("Next 24 hours"), value: "24h" },
        ]
        onActivated: page.cfg_lookahead = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_lookahead)
    }

    QQC2.SpinBox {
        id: maxTitleLength
        Kirigami.FormData.label: i18n("Maximum title length:")
        from: 10
        to: 100
    }

    QQC2.SpinBox {
        id: urgentThreshold
        Kirigami.FormData.label: i18n("Highlight when starting within (minutes):")
        from: 0
        to: 60
    }

    QQC2.TextField {
        id: placeholderText
        Kirigami.FormData.label: i18n("Text when no events:")
    }

    QQC2.SpinBox {
        id: popupDays
        Kirigami.FormData.label: i18n("Days shown in popup:")
        from: 1
        to: 14
    }
}
