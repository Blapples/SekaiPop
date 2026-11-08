import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Today's sunrise and sunset, from the same Open-Meteo reading as the Weather widget (so it
// uses the Location and the 12 / 24-hour setting you already picked). It starts from the last
// reading anyone made (services/WeatherCache.qml), so it is there when the lock is. Nothing is
// drawn until there is a reading (the editor shows a sample).
LockWidget {
    id: root

    readonly property bool hasReading: weather.sunriseText !== "" && weather.sunsetText !== ""
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
            spacing: root.px(14)

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "wb_twilight"
                size: root.px(44)
                weight: 600
                color: LockPalette.mint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hasReading ? weather.sunriseText : "6:05 AM"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(34)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Item {
                width: root.px(14)
                height: 1
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "bedtime"
                size: root.px(44)
                weight: 600
                color: LockPalette.lavenderText
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hasReading ? weather.sunsetText : "5:32 PM"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(34)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }
    }
}
