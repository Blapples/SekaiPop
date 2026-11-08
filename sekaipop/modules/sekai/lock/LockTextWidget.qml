import QtQuick
import qs.modules.common

// A line of your own words (a greeting, "if found, call ..."). Options: `text` (up to 120
// characters), `size` (small | medium | large). Read-only: it is drawn, never typed into,
// so nothing typed on the lockscreen can land in it.
LockWidget {
    id: root

    readonly property string value: String(root.opt("text", ""))
    readonly property bool shown: root.value !== "" || root.preview
    readonly property string label: root.value !== "" ? root.value : "Text"
    readonly property int pixelSize: {
        const s = root.opt("size", "medium")
        return root.px(s === "small" ? 34 : (s === "large" ? 84 : 54))
    }

    implicitWidth: root.shown ? face.width : 0
    implicitHeight: root.shown ? face.height : 0

    // The soft shadow behind the words, so they read on any wallpaper.
    Text {
        visible: root.shown
        x: root.px(3)
        y: root.px(4)
        width: face.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.label
        color: LockPalette.periwinkle
        opacity: 0.7
        font: face.font
    }

    Text {
        id: face
        visible: root.shown
        width: Math.min(implicitWidth, root.px(1100))
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.label
        color: "white"
        font.family: Theme.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }
}
