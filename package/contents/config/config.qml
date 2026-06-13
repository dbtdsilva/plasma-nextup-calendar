/*
    SPDX-FileCopyrightText: 2026 Diogo Silva <diogo.silva@loxy.cloud>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "view-calendar-upcoming"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Calendars")
        icon: "office-calendar"
        source: "configCalendars.qml"
    }
}
