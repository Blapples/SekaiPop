import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The weather now: an icon and the temperature, with the condition after it. Options:
// `condition` (the words), `place` (the city name; off by default, a locked screen is one
// anybody can see). It has its own WeatherSource, built when the lockscreen is. That source
// starts from the last reading anyone made (services/WeatherCache.qml), so the capsule is
// there the moment the lock is, and it only asks Open-Meteo again if that reading is older
// than 5 minutes (a failed try is tried again soon). Nothing is drawn until there is a
// reading (a failed or missing one leaves no gap-toothed capsule).
LockWidget {
    id: root

    readonly property bool hasReading: weather.temperatureText !== ""
    readonly property bool shown: root.hasReading || root.preview

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    WeatherSource {
        id: weather
    }

    LockCapsule {
        id: cap
        visible: root.shown
        width: row.implicitWidth + root.capPad * 2
        height: root.capH

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.px(16)

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.hasReading ? weather.iconName : "partly_cloudy_day"
                size: root.px(48)
                weight: 600
                color: LockPalette.lavenderText
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hasReading ? weather.temperatureText : "21°C"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(40)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Column {
                visible: root.opt("condition", true) === true || (root.opt("place", false) === true && weather.areaText !== "")
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    visible: root.opt("condition", true) === true
                    text: root.hasReading ? weather.conditionText : "Partly cloudy"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(22)
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    visible: root.opt("place", false) === true && (weather.areaText !== "" || root.preview)
                    text: weather.areaText !== "" ? weather.areaText : "Your city"
                    color: LockPalette.lavenderText
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(22)
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }
    }
}
