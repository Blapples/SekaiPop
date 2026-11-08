import Quickshell
import QtQuick
import qs.modules.common

// "Good morning", "Good afternoon", "Good evening" or "Good night" by the hour, with your
// name if you like. Option `name`: add the name (your login name, as the User widget shows).
LockWidget {
    id: root

    readonly property string userName: {
        const n = Quickshell.env("USER") || ""
        return n.length > 0 ? n.charAt(0).toUpperCase() + n.slice(1) : ""
    }

    readonly property string greeting: {
        const h = root.now.getHours()
        if (h >= 5 && h < 12)
            return "Good morning"
        if (h >= 12 && h < 18)
            return "Good afternoon"
        if (h >= 18 && h < 22)
            return "Good evening"
        return "Good night"
    }

    readonly property string line: root.opt("name", true) === true && root.userName !== "" ? root.greeting + ", " + root.userName : root.greeting

    implicitWidth: cap.width
    implicitHeight: cap.height

    LockCapsule {
        id: cap
        width: label.implicitWidth + root.capPad * 2
        height: root.capH

        Text {
            id: label
            anchors.centerIn: parent
            text: root.line
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: root.px(40)
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }
}
