import QtQuick
import qs.services
import qs.modules.common

// The keyboard layout you are typing in ("EN", "RU"), a small tag on the corner of the
// password plate. A password typed on the wrong layout is the most common reason a right
// one fails, and nothing else on the lockscreen says which is active. Hidden when there
// is only one layout configured (KeyboardLayoutService.code is empty then).
//
// A click opens a list above the tag with every layout (KeyboardLayoutService.layouts) and
// picks the one you press. The lockscreen has no bar to click, and a layout key only works
// here if its Hyprland bind was made for a locked session. The list is not a window: the
// session lock's surface can't host a popup, so it is drawn inside the look, in `overlay`
// (the look's own root), above everything else, with a sheet behind it that closes it on a
// press anywhere else. The two looks colour the tag and the list to match their own plates.
Rectangle {
    id: root

    // The look's root item: the list and the sheet behind it live there, not under this tag
    // (the plate this tag is on shakes, and draws things over it).
    required property Item overlay

    property color fillColor: LockPalette.pink
    property color textColor: "white"
    property int fontPixelSize: 18
    property int tagHeight: 30
    property int sidePadding: 26

    // The list's own colours: the plate, the writing on it, the row that is on, a hard shadow.
    property color panelColor: LockPalette.paper
    property color inkColor: LockPalette.cBorder
    property color accentColor: LockPalette.mint
    property color shadowColor: LockPalette.shadow
    property int shadowDy: 6
    property int panelRadius: 16

    readonly property string code: KeyboardLayoutService.code
    property bool open: false

    // The look puts the keyboard back on itself: a press here is taken by this tag, so the
    // look's own "anywhere you click" never sees it.
    signal activated()

    visible: root.code !== ""
    implicitWidth: label.implicitWidth + root.sidePadding
    implicitHeight: root.tagHeight
    radius: height / 2
    color: root.fillColor

    onVisibleChanged: if (!root.visible) root.open = false

    function toggle() {
        if (root.open) {
            root.open = false
            return
        }
        // Where the tag is in the look now, so the list opens right above its right edge.
        const p = root.mapToItem(root.overlay, root.width, 0)
        list.x = Math.max(0, p.x - list.width)
        list.y = Math.max(0, p.y - list.height - Math.round(root.tagHeight * 0.4))
        root.open = true
    }

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

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.toggle()
            root.activated()
        }
    }

    // A press anywhere else puts the list away (and the keyboard back on the look).
    MouseArea {
        parent: root.overlay
        anchors.fill: parent
        z: 998
        visible: root.open
        onPressed: {
            root.open = false
            root.activated()
        }
    }

    Item {
        id: list
        parent: root.overlay
        z: 999
        visible: root.open

        readonly property int rowH: Math.round(root.tagHeight * 1.2)
        readonly property int pad: Math.round(root.tagHeight * 0.25)

        width: Math.round(root.fontPixelSize * 14)
        height: rows.count * list.rowH + 2 * list.pad

        Rectangle {
            y: root.shadowDy
            width: parent.width
            height: parent.height
            radius: root.panelRadius
            color: root.shadowColor
        }

        Rectangle {
            anchors.fill: parent
            radius: root.panelRadius
            color: root.panelColor
            border.width: 2
            border.color: root.inkColor
        }

        // Presses on the panel's own gaps stay on the panel instead of closing it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            x: list.pad
            y: list.pad
            width: parent.width - 2 * list.pad

            Repeater {
                id: rows
                model: KeyboardLayoutService.layouts

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    readonly property bool current: row.modelData.index === KeyboardLayoutService.activeIndex

                    width: parent.width
                    height: list.rowH
                    radius: height / 2
                    color: row.current ? root.accentColor
                         : (area.containsMouse ? Qt.rgba(root.inkColor.r, root.inkColor.g, root.inkColor.b, 0.1) : "transparent")

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: root.sidePadding * 0.6
                        anchors.right: idText.visible ? idText.left : parent.right
                        anchors.rightMargin: root.sidePadding * 0.4
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.modelData.label
                        color: root.inkColor
                        font.family: Theme.fontFamily
                        font.pixelSize: root.fontPixelSize
                        font.weight: row.current ? Font.ExtraBold : Font.Bold
                        font.styleName: Theme.fontStyleBold
                    }

                    Text {
                        id: idText
                        anchors.right: parent.right
                        anchors.rightMargin: root.sidePadding * 0.6
                        anchors.verticalCenter: parent.verticalCenter
                        // A layout with no name here is already shown as its code.
                        visible: row.modelData.label !== row.modelData.id
                        text: row.modelData.id.toUpperCase()
                        color: root.inkColor
                        opacity: 0.6
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(root.fontPixelSize * 0.8)
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            KeyboardLayoutService.select(row.modelData.index)
                            root.open = false
                            root.activated()
                        }
                    }
                }
            }
        }
    }
}
