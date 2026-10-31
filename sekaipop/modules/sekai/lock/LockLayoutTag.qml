import QtQuick
import qs.services
import qs.modules.common

// The keyboard layout you are typing in ("EN", "RU"), a small tag on the corner of the
// password plate. A password typed on the wrong layout is the most common reason a right
// one fails, and nothing else on the lockscreen says which is active. Hidden when there
// is only one layout configured (KeyboardLayoutService.code is empty then). The two looks
// colour it to match their own plates; the lockscreen has no other use for it.
Rectangle {
    id: root

    property color fillColor: LockPalette.pink
    property color textColor: "white"
    property int fontPixelSize: 18
    property int tagHeight: 30
    property int sidePadding: 26

    readonly property string code: KeyboardLayoutService.code

    visible: root.code !== ""
    implicitWidth: label.implicitWidth + root.sidePadding
    implicitHeight: root.tagHeight
    radius: height / 2
    color: root.fillColor

    Text {
        id: label
        anchors.centerIn: parent
        text: root.code
        color: root.textColor
        font.family: Theme.fontFamily
        font.pixelSize: root.fontPixelSize
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }
}
