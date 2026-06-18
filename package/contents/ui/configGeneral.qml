/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
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
    property alias cfg_panelHideAllDay: panelHideAllDay.checked
    property alias cfg_popupHideAllDay: popupHideAllDay.checked
    property alias cfg_alertEnabled: alertEnabled.checked

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Next up (panel)")
        Kirigami.FormData.isSection: true
    }

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
        Kirigami.FormData.label: i18n("Mark the next event imminent within (minutes):")
        from: 0
        to: 60
    }

    QQC2.TextField {
        id: placeholderText
        Kirigami.FormData.label: i18n("Text when no events:")
    }

    QQC2.CheckBox {
        id: panelHideAllDay
        Kirigami.FormData.label: i18n("Hide all-day events:")
        text: i18n("Don't show all-day events in the panel")
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Agenda popup")
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: popupDays
        Kirigami.FormData.label: i18n("Days shown in popup:")
        from: 1
        to: 14
    }

    QQC2.CheckBox {
        id: popupHideAllDay
        Kirigami.FormData.label: i18n("Hide all-day events:")
        text: i18n("Don't show all-day events in the agenda")
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Alert")
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: alertEnabled
        Kirigami.FormData.label: i18n("Notify when imminent:")
        text: i18n("Show a desktop notification")
    }
}
