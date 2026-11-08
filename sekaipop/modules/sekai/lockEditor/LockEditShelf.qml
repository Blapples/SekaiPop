import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCanvasModel.js" as LM

// The lockscreen editor's shelf: a long card along the bottom, in Edit Desktop's look
// (EditTray.qml).
//
//   left      the title, and three lines of how-to
//   keys      one key per widget the lockscreen can have: click adds it (or selects it, if it
//             can only be there once and already is); press and drag it onto the card to put
//             it where you let go. A number says how many are on already; a dim key is full.
//   options   LockEditOptions.qml: what you can change about what is selected
//   right     Undo, Redo, Reset layout, "this monitor only" (with more than one monitor), Done
//
// The shelf has the design pixels of the rest of the shell; the stage scales it (`ScaleHost`).
// Dragging a key reports where the pointer is (window pixels) through `dragKind`, `dragX` and
// `dragY`, and, on release, `dropped(kind, x, y)`; the stage draws the ghost and does the
// dropping, because it knows where the card is.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // The key being dragged off the shelf ("" = none) and where the pointer is.
    property string dragKind: ""
    property real dragX: 0
    property real dragY: 0
    readonly property bool typing: options.typing

    signal dropped(string kind, real x, real y)
    signal done()

    // One line of the how-to: a keycap, then what it does.
    component HintRow: Item {
        id: hr

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string keyText: ""
        property string keyIcon: ""
        property string label: ""

        width: 214
        height: 26

        Pill {
            width: 34
            height: 26
            cornerRadius: 8
            ringWidth: 3
            shadowDy: 3
            fillColor: hr.mt.chipFill

            Text {
                anchors.centerIn: parent
                visible: hr.keyIcon === ""
                text: hr.keyText
                color: hr.mt.chipInk
                font.family: hr.mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: hr.mt.fontStyleBold
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: hr.keyIcon !== ""
                name: hr.keyIcon
                size: 13
                weight: 700
                color: hr.mt.chipInk
            }
        }

        Text {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            text: hr.label
            color: hr.mt.pInk
            font.family: hr.mt.fontFamily
            font.pixelSize: 12
            font.weight: Font.ExtraBold
            font.styleName: hr.mt.fontStyleBold
        }
    }

    // A widget's key: its icon over its name, in the same look as Edit Desktop's tab keys.
    component KindKey: Item {
        id: kk

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        // The shelf (an inline component can not see the file's ids, so it is passed in).
        property var host: null
        property var info: null

        readonly property int count: kk.info ? LockEditService.countOf(kk.info.kind) : 0
        readonly property bool full: kk.info ? !LockEditService.canAdd(kk.info.kind) : true
        readonly property bool dragging: kk.host !== null && kk.host.dragKind === (kk.info ? kk.info.kind : "-")

        width: 98
        height: 62
        opacity: kk.full && !kk.dragging ? 0.6 : 1

        Pill {
            anchors.fill: parent
            cornerRadius: 15
            ringWidth: 7
            shadowDy: 4
            pressed: area.pressed
            fillColor: area.containsMouse || kk.dragging ? kk.mt.pSurfaceHover : kk.mt.pSurface

            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                spacing: 1

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: kk.info ? kk.info.icon : ""
                    size: 24
                    weight: 600
                    color: kk.mt.pInk
                }

                Text {
                    width: 78
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: kk.info ? kk.info.title.toUpperCase() : ""
                    color: kk.mt.pInk
                    font.family: kk.mt.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.styleName: kk.mt.fontStyleBold
                    font.letterSpacing: 0.4
                }
            }
        }

        // How many are on the lockscreen already.
        Rectangle {
            visible: kk.count > 0
            x: parent.width - width + 6
            y: -6
            width: Math.max(20, badgeText.implicitWidth + 10)
            height: 20
            radius: 10
            color: kk.mt.accentMint
            border.width: 2
            border.color: kk.mt.colBorder

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: kk.count
                color: kk.mt.colBorder
                font.family: kk.mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: kk.mt.fontStyleBold
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            property real pressX: 0
            property real pressY: 0
            property bool pulled: false
            // A drag that ends back over the key must not also count as a click.
            property bool wasDrag: false

            onPressed: mouse => {
                const p = area.mapToItem(null, mouse.x, mouse.y)
                area.pressX = p.x
                area.pressY = p.y
                area.pulled = false
                area.wasDrag = false
            }

            onPositionChanged: mouse => {
                if (!area.pressed || !kk.host || !kk.info)
                    return
                const p = area.mapToItem(null, mouse.x, mouse.y)
                // Far enough to be a drag and not a click: a full key can not be dragged.
                if (!area.pulled && Math.abs(p.x - area.pressX) + Math.abs(p.y - area.pressY) > 14) {
                    if (kk.full)
                        return
                    area.pulled = true
                    kk.host.dragKind = kk.info.kind
                }
                if (area.pulled) {
                    kk.host.dragX = p.x
                    kk.host.dragY = p.y
                }
            }

            onReleased: mouse => {
                if (!area.pulled || !kk.host || !kk.info)
                    return
                const p = area.mapToItem(null, mouse.x, mouse.y)
                const kind = kk.info.kind
                area.pulled = false
                area.wasDrag = true
                kk.host.dragKind = ""
                kk.host.dropped(kind, p.x, p.y)
            }

            onCanceled: {
                area.pulled = false
                if (kk.host)
                    kk.host.dragKind = ""
            }

            onClicked: {
                if (!area.pulled && !area.wasDrag && kk.info)
                    LockEditService.addOrSelect(kk.info.kind)
            }
        }
    }

    // A key on the right: an icon and a word, mint when it is on.
    component ActionKey: Item {
        id: ak

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string icon: ""
        property string label: ""
        property bool on: false
        property bool dim: false
        property bool accent: false

        signal activated()

        height: 36
        opacity: ak.dim ? 0.45 : 1

        Gradient {
            id: fill
            GradientStop { position: 0.0; color: ak.mt.accentMint }
            GradientStop { position: 1.0; color: ak.mt.accentCyan }
        }

        Pill {
            anchors.fill: parent
            cornerRadius: 12
            ringWidth: 4
            shadowDy: 3
            pressed: akArea.pressed && !ak.dim
            fillColor: akArea.containsMouse && !ak.on && !ak.dim ? ak.mt.pSurfaceHover : ak.mt.pSurface
            fillGradient: ak.on || ak.accent ? fill : null

            Row {
                anchors.centerIn: parent
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ak.icon !== ""
                    name: ak.icon
                    size: 17
                    weight: 600
                    color: ak.on || ak.accent ? ak.mt.colBorder : ak.mt.pInk
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ak.label !== ""
                    text: ak.label
                    color: ak.on || ak.accent ? ak.mt.colBorder : ak.mt.pInk
                    font.family: ak.mt.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.styleName: ak.mt.fontStyleBold
                    font.letterSpacing: 0.6
                }
            }
        }

        MouseArea {
            id: akArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !ak.dim
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: ak.activated()
        }
    }

    // ===== the card =====
    Pill {
        id: tray

        // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
        readonly property bool classicPanel: true

        x: 22
        width: parent.width - 44
        height: 192
        y: parent.height - 14 - tray.height

        cornerRadius: root.mt.radiusOuter
        ringWidth: root.mt.borderWidth + root.mt.outerRingWidth
        ringColorTop: root.mt.pSurfaceRing
        ringColorBottom: ringColorTop
        fillColor: root.mt.pSurface

        // A click on a bare part of the shelf is the shelf's: it must not reach the stage
        // behind it, which would let go of what is selected.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        // ===== left: the title and the how-to =====
        Column {
            id: info
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 214
            spacing: 6

            Item {
                width: info.width
                height: 38

                Rectangle {
                    id: headDiamond
                    x: 4
                    y: 4
                    width: 16
                    height: 16
                    radius: 4
                    rotation: 45
                    color: root.mt.accentMint
                    border.width: 2
                    border.color: root.mt.pLine
                    antialiasing: true
                }

                Text {
                    anchors.left: headDiamond.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: headDiamond.verticalCenter
                    text: "EDIT LOCKSCREEN"
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                    font.styleName: root.mt.fontStyleBold
                }

                Text {
                    y: 25
                    width: parent.width
                    elide: Text.ElideRight
                    text: LockEditService.ownBoard ? "Only for " + LockEditService.screenName : "Pick it, place it, tweak it."
                    color: root.mt.pInkSub
                    font.family: root.mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            HintRow {
                keyIcon: "open_with"
                label: "Drag: move (Shift: free)"
            }

            HintRow {
                keyIcon: "mouse"
                label: "Wheel: resize"
            }

            HintRow {
                keyText: "R"
                label: "Right click: remove"
            }
        }

        Rectangle {
            id: dividerLeft
            x: 16 + 214 + 14
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 132
            radius: 1
            color: root.mt.pSurfaceDivider
        }

        // ===== the middle: keys, then options =====
        readonly property real midX: dividerLeft.x + 16
        readonly property real midW: actions.x - 16 - tray.midX
        // Every key in one row when there is room for them and the options; else two rows.
        readonly property int keyCount: Math.max(4, LockEditService.catalog.length)
        readonly property real keysW: Math.max(4 * 98 + 3 * 8, Math.min(tray.keyCount * 98 + (tray.keyCount - 1) * 8, tray.midW - 420 - 28))

        Flow {
            id: keys
            x: tray.midX
            anchors.verticalCenter: parent.verticalCenter
            width: tray.keysW
            spacing: 8

            Repeater {
                model: LockEditService.catalog

                KindKey {
                    required property var modelData

                    host: root
                    info: modelData
                }
            }
        }

        LockEditOptions {
            id: options
            x: tray.midX + tray.keysW + 28
            width: Math.max(300, tray.midW - tray.keysW - 28)
            height: parent.height - 28
            anchors.verticalCenter: parent.verticalCenter
        }

        // ===== right: undo, redo, reset, done =====
        Rectangle {
            id: dividerRight
            x: actions.x - 16
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 132
            radius: 1
            color: root.mt.pSurfaceDivider
        }

        Column {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 170
            spacing: 8

            Row {
                spacing: 8

                ActionKey {
                    width: 81
                    icon: "undo"
                    label: ""
                    dim: !LockEditService.canUndo
                    onActivated: LockEditService.undo()
                }

                ActionKey {
                    width: 81
                    icon: "redo"
                    label: ""
                    dim: !LockEditService.canRedo
                    onActivated: LockEditService.redo()
                }
            }

            Row {
                spacing: 8

                ActionKey {
                    width: LockEditService.monitorCount > 1 ? 81 : actions.width
                    icon: "restart_alt"
                    label: "RESET"
                    onActivated: LockEditService.resetLayout()
                }

                ActionKey {
                    visible: LockEditService.monitorCount > 1
                    width: 81
                    icon: "desktop_windows"
                    label: "THIS"
                    on: LockEditService.ownBoard
                    onActivated: LockEditService.setOwnBoard(!LockEditService.ownBoard)
                }
            }

            Item {
                width: actions.width
                height: 54

                Pill {
                    anchors.fill: parent
                    cornerRadius: 15
                    ringWidth: 4
                    shadowDy: 4
                    pressed: doneArea.pressed
                    fillGradient: Gradient {
                        GradientStop { position: 0.0; color: root.mt.accentMint }
                        GradientStop { position: 1.0; color: root.mt.accentCyan }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: 22
                            weight: 700
                            color: root.mt.colBorder
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "DONE"
                            color: root.mt.colBorder
                            font.family: root.mt.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.ExtraBold
                            font.styleName: root.mt.fontStyleBold
                            font.letterSpacing: 1
                        }
                    }
                }

                MouseArea {
                    id: doneArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.done()
                }
            }
        }
    }
}
