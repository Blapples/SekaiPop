import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// The battery: an icon and the percentage. Only on a machine with a battery (a desktop PC
// shows nothing), and always in the editor. Option `percent`: the number.
LockWidget {
    id: root

    readonly property bool present: root.battery !== null && root.battery.available
    readonly property bool shown: root.present || root.preview
    readonly property int percentage: root.present ? root.battery.percentage : 80
    readonly property bool charging: root.present && root.battery.isCharging
    readonly property bool low: root.present && root.battery.isLow

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockCapsule {
        id: cap
        visible: root.shown
        width: row.implicitWidth + root.capPad * 2
        height: root.capH

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.px(12)

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.charging ? "battery_android_frame_bolt" : "battery_android_full"
                size: root.px(44)
                weight: 600
                color: root.low ? LockPalette.pink : (root.charging ? LockPalette.mint : "white")
            }

            Text {
                visible: root.opt("percent", true) === true
                anchors.verticalCenter: parent.verticalCenter
                text: root.percentage + "%"
                color: root.low ? LockPalette.pink : "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(40)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }
    }
}
