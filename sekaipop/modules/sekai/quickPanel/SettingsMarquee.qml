import QtQuick

// A single clipped settings label, readable in full on hover.
Item {
    id: view

    property alias text: textItem.text
    property alias color: textItem.color
    property alias font: textItem.font
    property alias lineHeight: textItem.lineHeight
    property bool hovered: false
    property bool ready: false
    readonly property real overflow: Math.max(0, textItem.implicitWidth - width)
    readonly property bool scrolling: hovered && ready && overflow > 1

    implicitHeight: textItem.implicitHeight
    clip: true

    onHoveredChanged: if (!hovered) ready = false
    onTextChanged: ready = false
    onWidthChanged: ready = false
    onScrollingChanged: if (!scrolling) textItem.x = 0

    Timer {
        interval: 650
        running: view.hovered && view.overflow > 1 && !view.ready
        onTriggered: view.ready = true
    }

    Text {
        id: textItem
        width: view.scrolling ? implicitWidth : view.width
        elide: view.scrolling ? Text.ElideNone : Text.ElideRight
        textFormat: Text.PlainText
        wrapMode: Text.NoWrap
        lineHeightMode: Text.FixedHeight
    }

    SequentialAnimation {
        running: view.scrolling
        loops: Animation.Infinite
        NumberAnimation {
            target: textItem
            property: "x"
            from: 0
            to: -view.overflow
            duration: Math.max(400, view.overflow / 35 * 1000)
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 1200 }
        NumberAnimation {
            target: textItem
            property: "x"
            to: 0
            duration: Math.max(400, view.overflow / 35 * 1000)
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 900 }
    }
}
