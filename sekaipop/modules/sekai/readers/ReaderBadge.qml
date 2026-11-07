import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// A little stamp stuck on a cover: outlined, a touch tilted, in the shell's accent colours,
// like the stickers on the popups. Drop it on a CoverCard and anchor it to a corner.
//
// Two looks (see ReaderType): the solid accent stamp is for the one thing a screen wants seen
// (the score); `tonal` is a dark stamp with light text for information (status, year, tracked,
// last read), with an optional coloured line via `outline`.
Rectangle {
    id: root

    property string text: ""
    property bool tonal: false
    property color fill: root.tonal ? Theme.surfaceHover : Theme.accentMint
    property color ink: root.tonal ? Theme.ink : Theme.colBorder
    property color outline: Theme.colBorder

    implicitHeight: ReaderType.hBadge
    implicitWidth: label.implicitWidth + 16
    radius: 9
    color: root.fill
    border.width: 2
    border.color: root.outline
    rotation: 4
    antialiasing: true

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.ink
        font.family: Theme.fontFamily
        font.pixelSize: ReaderType.sizeCaption
        font.letterSpacing: 0.5
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }
}
