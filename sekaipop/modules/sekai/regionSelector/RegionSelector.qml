import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The screen-region picker (state and actions: services/RegionService.qml).
// One full-screen overlay per monitor, built only while the picker is open.
// Each one:
//   1. takes a picture of its monitor (grim) and shows it frozen, dimmed;
//   2. lets you drag a rectangle, or click a window to take it whole;
//   3. shows a toolbar under the selection: Copy, Save, Copy text, Image
//      search, Record, Record with sound. The one the key / IPC call asked for
//      is lit; Enter runs it, a click runs the one clicked.
// Escape (or a plain right click) cancels. Right-drag a region instead and it
// goes straight to swappy for annotating, no toolbar.
//
// Drag a selection by its edges / corners to resize it, or by the middle to move
// it; hold nothing, there are no modifier keys to learn.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: loader
            required property var modelData
            active: RegionService.open
            sourceComponent: RegionWindow {
                screen: loader.modelData
            }
        }
    }

    component RegionWindow: PanelWindow {
        id: win

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sekaipop-region"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }

        readonly property string pic: RegionService.tmpDir + "/shot-" + (screen ? screen.name : "x") + ".png"
        property bool shotReady: false
        // The frozen picture's own pixels per logical pixel.
        readonly property real pixelsPerPoint: shotImage.status === Image.Ready && width > 0
            ? shotImage.implicitWidth / width : (screen ? screen.devicePixelRatio : 1)

        // ===== the selection =====
        property bool hasSel: false
        property real selX: 0
        property real selY: 0
        property real selW: 0
        property real selH: 0
        property bool dragging: false
        property real anchorX: 0
        property real anchorY: 0
        // "new", "move", or an edge / corner of the existing selection
        property string dragKind: "new"
        property real grabDX: 0
        property real grabDY: 0
        // The window under the pointer (before anything is dragged).
        property var hoverRect: null
        // The action lit in the toolbar.
        property string lit: RegionService.action

        readonly property real minSize: 4

        Component.onCompleted: {
            HyprlandData.active = true
            grabber.exec(["sh", RegionService.script, "capture", win.screen.name, win.pic])
        }
        Component.onDestruction: HyprlandData.active = false

        Process {
            id: grabber
            onExited: code => win.shotReady = (code === 0)
        }

        // Windows on this monitor's active workspace, in this window's pixels.
        readonly property var windowRects: {
            if (!win.screen)
                return []
            const mon = Hyprland.monitorFor(win.screen)
            const ws = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
            const list = (HyprlandData.windowList || []).filter(w => w.mapped !== false && w.workspace && w.workspace.id === ws)
            // Floating windows are on top.
            list.sort((a, b) => (b.floating ? 1 : 0) - (a.floating ? 1 : 0))
            return list.map(w => ({ x: w.at[0] - win.screen.x, y: w.at[1] - win.screen.y, w: w.size[0], h: w.size[1] }))
        }

        function windowAt(px, py) {
            for (const r of win.windowRects)
                if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h)
                    return r
            return null
        }

        function setSel(x, y, w, h) {
            const nx = Math.max(0, Math.min(win.width - win.minSize, x))
            const ny = Math.max(0, Math.min(win.height - win.minSize, y))
            win.selX = nx
            win.selY = ny
            win.selW = Math.max(win.minSize, Math.min(win.width - nx, w))
            win.selH = Math.max(win.minSize, Math.min(win.height - ny, h))
            win.hasSel = true
        }

        function run(act) {
            if (!win.hasSel)
                return
            RegionService.run(act, win.screen, win.selX, win.selY, win.selW, win.selH, win.pic, win.pixelsPerPoint)
        }

        // Which part of the finished selection a point is on.
        function hitKind(px, py) {
            if (!win.hasSel)
                return "new"
            const mc = 16
            if (Math.abs(px - win.selX) <= mc && Math.abs(py - win.selY) <= mc) return "tl"
            if (Math.abs(px - (win.selX + win.selW)) <= mc && Math.abs(py - win.selY) <= mc) return "tr"
            if (Math.abs(px - win.selX) <= mc && Math.abs(py - (win.selY + win.selH)) <= mc) return "bl"
            if (Math.abs(px - (win.selX + win.selW)) <= mc && Math.abs(py - (win.selY + win.selH)) <= mc) return "br"
            const m = 8
            const l = Math.abs(px - win.selX) <= m
            const r = Math.abs(px - (win.selX + win.selW)) <= m
            const t = Math.abs(py - win.selY) <= m
            const b = Math.abs(py - (win.selY + win.selH)) <= m
            const inX = px >= win.selX - m && px <= win.selX + win.selW + m
            const inY = py >= win.selY - m && py <= win.selY + win.selH + m
            if (l && inY) return "l"
            if (r && inY) return "r"
            if (t && inX) return "t"
            if (b && inX) return "b"
            if (px > win.selX && px < win.selX + win.selW && py > win.selY && py < win.selY + win.selH)
                return "move"
            return "new"
        }

        // ===== picture + dimming =====
        Image {
            id: shotImage
            anchors.fill: parent
            source: win.shotReady ? ("file://" + win.pic) : ""
            cache: false
            asynchronous: false
            fillMode: Image.Stretch
        }

        // The dim, as four rectangles around the selection (the hole shows the
        // picture at full brightness).
        Item {
            anchors.fill: parent
            readonly property real hx: win.hasSel ? win.selX : (win.hoverRect ? win.hoverRect.x : 0)
            readonly property real hy: win.hasSel ? win.selY : (win.hoverRect ? win.hoverRect.y : 0)
            readonly property real hw: win.hasSel ? win.selW : (win.hoverRect ? win.hoverRect.w : 0)
            readonly property real hh: win.hasSel ? win.selH : (win.hoverRect ? win.hoverRect.h : 0)
            readonly property color dim: Qt.rgba(0, 0, 0, 0.48)

            Rectangle { x: 0; y: 0; width: parent.width; height: parent.hy; color: parent.dim }
            Rectangle { x: 0; y: parent.hy + parent.hh; width: parent.width; height: Math.max(0, parent.height - parent.hy - parent.hh); color: parent.dim }
            Rectangle { x: 0; y: parent.hy; width: parent.hx; height: parent.hh; color: parent.dim }
            Rectangle { x: parent.hx + parent.hw; y: parent.hy; width: Math.max(0, parent.width - parent.hx - parent.hw); height: parent.hh; color: parent.dim }
        }

        // Hovered window outline (only while nothing is selected yet).
        Rectangle {
            visible: !win.hasSel && win.hoverRect !== null && !win.dragging
            x: win.hoverRect ? win.hoverRect.x : 0
            y: win.hoverRect ? win.hoverRect.y : 0
            width: win.hoverRect ? win.hoverRect.w : 0
            height: win.hoverRect ? win.hoverRect.h : 0
            color: Qt.rgba(Theme.accentCyan.r, Theme.accentCyan.g, Theme.accentCyan.b, 0.14)
            border.width: 3
            border.color: Theme.accentCyan
            antialiasing: true
        }

        // The selection's frame.
        Rectangle {
            visible: win.hasSel
            x: win.selX
            y: win.selY
            width: win.selW
            height: win.selH
            color: "transparent"
            border.width: 3
            border.color: Theme.accentMint
            antialiasing: true

            // Corner knobs.
            Repeater {
                model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                delegate: Rectangle {
                    required property var modelData
                    width: 11
                    height: 11
                    radius: 3
                    x: modelData[0] * parent.width - width / 2
                    y: modelData[1] * parent.height - height / 2
                    color: Theme.colBorder
                    border.width: 2
                    border.color: Theme.textWhite
                }
            }
        }

        // The size tag.
        Rectangle {
            visible: win.hasSel
            readonly property bool above: win.selY > 34
            x: Math.max(4, Math.min(win.width - width - 4, win.selX))
            y: above ? win.selY - height - 6 : win.selY + 6
            radius: 7
            color: Theme.colBorder
            width: sizeText.implicitWidth + 14
            height: sizeText.implicitHeight + 8
            Text {
                id: sizeText
                anchors.centerIn: parent
                text: Math.round(win.selW * win.pixelsPerPoint) + " × " + Math.round(win.selH * win.pixelsPerPoint)
                color: Theme.textWhite
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        // ===== the mouse =====
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: {
                if (win.dragging)
                    return win.dragKind === "move" ? Qt.ClosedHandCursor : Qt.CrossCursor
                switch (win.hitKind(mouseX, mouseY)) {
                case "tl": case "br": return Qt.SizeFDiagCursor
                case "tr": case "bl": return Qt.SizeBDiagCursor
                case "l": case "r": return Qt.SizeHorCursor
                case "t": case "b": return Qt.SizeVerCursor
                case "move": return Qt.OpenHandCursor
                default: return Qt.CrossCursor
                }
            }

            property real pressX: 0
            property real pressY: 0
            property bool moved: false
            // The drag in progress was made with the right button (-> swappy).
            property bool rightDrag: false

            onPositionChanged: m => {
                if (!win.dragging) {
                    win.hoverRect = win.hasSel ? null : win.windowAt(m.x, m.y)
                    return
                }
                if (Math.abs(m.x - mouse.pressX) > 3 || Math.abs(m.y - mouse.pressY) > 3)
                    mouse.moved = true
                const k = win.dragKind
                if (k === "new") {
                    win.setSel(Math.min(win.anchorX, m.x), Math.min(win.anchorY, m.y),
                               Math.abs(m.x - win.anchorX), Math.abs(m.y - win.anchorY))
                } else if (k === "move") {
                    win.setSel(Math.max(0, Math.min(win.width - win.selW, m.x - win.grabDX)),
                               Math.max(0, Math.min(win.height - win.selH, m.y - win.grabDY)),
                               win.selW, win.selH)
                } else {
                    // Resizing: the edge(s) named follow the pointer, the others stay.
                    let l = win.selX, t = win.selY, r = win.selX + win.selW, b = win.selY + win.selH
                    if (k.indexOf("l") >= 0) l = Math.min(m.x, r - win.minSize)
                    if (k.indexOf("r") >= 0) r = Math.max(m.x, l + win.minSize)
                    if (k.indexOf("t") >= 0) t = Math.min(m.y, b - win.minSize)
                    if (k.indexOf("b") >= 0) b = Math.max(m.y, t + win.minSize)
                    win.setSel(l, t, r - l, b - t)
                }
            }

            onPressed: m => {
                if (m.button === Qt.RightButton) {
                    // A right-drag always starts a fresh region; it is sent to
                    // swappy on release. A right click with no drag cancels.
                    if (win.dragging)
                        return
                    mouse.rightDrag = true
                    mouse.pressX = m.x
                    mouse.pressY = m.y
                    mouse.moved = false
                    win.dragKind = "new"
                    win.dragging = true
                    win.hasSel = false
                    win.hoverRect = null
                    win.anchorX = m.x
                    win.anchorY = m.y
                    return
                }
                mouse.pressX = m.x
                mouse.pressY = m.y
                mouse.moved = false
                win.dragKind = win.hitKind(m.x, m.y)
                win.dragging = true
                if (win.dragKind === "new") {
                    win.hasSel = false
                    win.anchorX = m.x
                    win.anchorY = m.y
                } else if (win.dragKind === "move") {
                    win.grabDX = m.x - win.selX
                    win.grabDY = m.y - win.selY
                }
            }

            onReleased: m => {
                if (m.button === Qt.RightButton) {
                    if (!mouse.rightDrag)
                        return
                    mouse.rightDrag = false
                    win.dragging = false
                    if (mouse.moved && win.hasSel)
                        win.run("swappy")
                    else
                        RegionService.hide()
                    return
                }
                if (m.button !== Qt.LeftButton)
                    return
                win.dragging = false
                // A click with no drag takes the window under it, or does nothing.
                if (win.dragKind === "new" && !mouse.moved) {
                    const r = win.windowAt(m.x, m.y)
                    if (r) {
                        win.setSel(r.x, r.y, r.w, r.h)
                        win.hoverRect = null
                    } else {
                        win.hasSel = false
                    }
                }
            }
        }

        // ===== keys =====
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: RegionService.hide()
            Keys.onReturnPressed: win.run(win.lit)
            Keys.onEnterPressed: win.run(win.lit)
            Keys.onPressed: event => {
                // A letter for each action (its keycap is on the toolbar button):
                // with a region picked it runs at once; before that it only
                // lights the action, so the region you drag next goes to it
                // (Enter, or the lit button, runs it).
                if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                    return
                if (event.key < Qt.Key_A || event.key > Qt.Key_Z)
                    return
                const id = RegionService.actionForKey(String.fromCharCode(event.key),
                                                      (event.modifiers & Qt.ShiftModifier) !== 0)
                if (id === "")
                    return
                win.lit = id
                if (win.hasSel)
                    win.run(id)
                event.accepted = true
            }
        }

        // ===== the toolbar =====
        Item {
            id: bar
            visible: win.hasSel && !win.dragging
            // Where it goes: just under the selection if there is room. Where
            // there isn't (the selection reaches the bottom of the screen, a
            // full-screen grab) it sits inside the selection's bottom edge,
            // above the dock if the dock is in the way, never on it. A
            // selection too short for that puts it above the selection.
            readonly property real selBottom: win.selY + win.selH
            readonly property real wantY: selBottom + 14
            // The dock is in the picture on this screen only, and only matters
            // if the toolbar is over it sideways.
            readonly property var dockInfo: win.screen ? (RegionService.docks[win.screen.name] ?? null) : null
            readonly property bool dockShown: dockInfo !== null
            readonly property real dockEdge: dockShown ? win.height - dockInfo.top : win.height
            readonly property bool overDock: dockShown
                && x + width > win.width / 2 - dockInfo.half - 12
                && x < win.width / 2 + dockInfo.half + 12
            // Lowest y the toolbar's bottom edge may reach on its way down.
            readonly property real floorY: overDock ? dockEdge - 14 : win.height - 6
            readonly property bool below: wantY + height <= floorY
            readonly property real insideY: Math.min(selBottom - 14, floorY) - height
            readonly property bool insideFits: win.selH >= height + 40 && insideY >= win.selY + 8
            x: Math.max(8, Math.min(win.width - width - 8, win.selX + win.selW / 2 - width / 2))
            y: below ? wantY
               : (insideFits ? insideY : Math.max(8, win.selY - height - 14 - 28))
            width: row.width
            height: 34 + Theme.shadowOffset

            Row {
                id: row
                spacing: 6

                Repeater {
                    model: RegionService.actions

                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property bool isLit: win.lit === modelData.id
                        readonly property bool expanded: isLit || cellArea.containsMouse
                        width: 34 + labelBox.width
                        height: 34

                        Pill {
                            anchors.fill: parent
                            anchors.bottomMargin: -Theme.shadowOffset
                            cornerRadius: 12
                            ringWidth: 4
                            fillColor: cell.isLit ? Theme.accentMint : (cellArea.containsMouse ? Theme.surfaceHover : Theme.surface)
                            pressed: cellArea.pressed
                            Row {
                                anchors.centerIn: parent
                                spacing: 0
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: cell.modelData.icon
                                    size: 18
                                    fill: cell.isLit ? 1 : 0
                                    color: cell.isLit ? Theme.colBorder : Theme.ink
                                }
                                // The name slides out to the right of the icon.
                                Item {
                                    id: labelBox
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: label.implicitHeight
                                    width: cell.expanded ? label.implicitWidth + 5 : 0
                                    clip: true
                                    Behavior on width {
                                        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                    }
                                    Text {
                                        id: label
                                        x: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cell.modelData.label
                                        opacity: cell.expanded ? 1 : 0
                                        Behavior on opacity {
                                            NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                                        }
                                        // Navy only on the lit (mint) button; on the others the label
                                        // follows the theme's ink like the icon does, otherwise it is
                                        // navy on a dark button in dark mode and can't be seen.
                                        color: cell.isLit ? Theme.colBorder : Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.ExtraBold
                                        font.styleName: Theme.fontStyleBold
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win.lit = cell.modelData.id
                                win.run(cell.modelData.id)
                            }
                        }

                        // The key that picks this action: a small keycap on the
                        // button's top right corner (the same look as the bar's
                        // count badges). Drawn over the button, never in the way
                        // of a click.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -6
                            anchors.rightMargin: -5
                            width: 16
                            height: 16
                            radius: 5
                            color: cell.isLit ? Theme.accentMint : Theme.colBorder
                            border.width: 2
                            border.color: Theme.ringWhite
                            antialiasing: true

                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.keys[0]
                                color: cell.isLit ? Theme.colBorder : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                            }
                        }
                    }
                }
            }
        }

        // A tiny hint until a region is picked.
        Rectangle {
            visible: !win.hasSel && !win.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            y: 28
            radius: 10
            color: Theme.colBorder
            width: hintText.implicitWidth + 24
            height: hintText.implicitHeight + 14
            Text {
                id: hintText
                anchors.centerIn: parent
                text: "Drag a region or click a window  ·  Right-drag to annotate  ·  Esc cancels"
                color: Theme.textWhite
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }
    }
}
