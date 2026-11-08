import QtQuick
import qs.modules.common

// Today's date in a capsule. Option `style`: long ("Saturday, November 7") | short ("Sat, Nov 7").
LockWidget {
    id: root

    implicitWidth: cap.width
    implicitHeight: cap.height

    LockCapsule {
        id: cap
        width: label.implicitWidth + root.capPad * 2
        height: root.capH

        Text {
            id: label
            anchors.centerIn: parent
            text: Qt.formatDateTime(root.now, root.opt("style", "long") === "short" ? "ddd, MMM d" : "dddd, MMMM d")
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: root.px(40)
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }
}
