import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The "Ch. 12" / "Not started" strip along the bottom of a CoverCard. `started` drives the
// whole read/unread treatment: a started title gets an accent diamond and full ink, one not
// started a pale outlined diamond and a muted line. Divided from the cover by the panel line.
Rectangle {
    id: root

    // Deliberately `var`, not `bool`: call sites pass the chapter/episode number
    // straight through and the ternaries below apply JS truthiness, exactly as the
    // inlined versions did. A `bool` property would route through Qt's string
    // conversion instead, which turns "0" into false.
    property var started: false
    property string label: ""
    property string bodyFont: Theme.fontFamily
    property int rowSpacing: 6

    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
    height: 30
    color: root.started ? Theme.surfaceTint : Theme.surfaceHover

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 2
        color: Theme.line
    }

    Row {
        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: 1
            left: parent.left; leftMargin: 10
        }
        spacing: root.rowSpacing + 2

        DiamondDot {
            anchors.verticalCenter: parent.verticalCenter
            size: 8
            lit: root.started ? true : false
            litColor: Theme.accentMint
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: root.bodyFont
            font.pixelSize: 10
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
            color: root.started ? Theme.ink : Theme.inkSub
        }
    }
}
