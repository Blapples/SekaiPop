import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCanvasModel.js" as LM
import "../../common/functions/LockEditMath.js" as EM
import qs.modules.sekai.lock

// Everything the lockscreen editor shows, inside its window (LockEditor.qml):
//
//   the stage     dark navy with diamonds, like Edit Desktop's
//   the card      the lockscreen as a framed card: the wallpaper, the widgets and the password
//                 block, all drawn at the screen's real size and scaled down as one picture
//                 (`view`), so a widget is as big on it, next to the screen, as it will be when
//                 locked. Widgets are the lock's own Lock*Widget files, in preview mode.
//   the shelf     LockEditShelf.qml
//
// Opening works like Edit Desktop's (EditMode.qml): the card starts as the whole screen and
// shrinks into its place (a little past it, then settling back), the frame grows round it, the
// stage comes in behind and the shelf rises from the bottom edge. Closing runs it backwards.
// All of it follows `LockEditService.progress`; nothing here has a timer of its own.
//
// Everything on the card works in SCREEN pixels (`sw` x `sh`): a pointer position is mapped into
// `view` first, so the maths (LockEditMath.js) never sees the card's scale.
//
// Keys: Esc (let go of what is selected, then leave), Tab / Shift+Tab (select the next one),
// arrows (move, with Shift ten times as far), + and - (resize), Delete (remove), Ctrl+Z and
// Ctrl+Shift+Z or Ctrl+Y (undo, redo).
//
// This is not the lockscreen: the real one is LockCanvas.qml, which never has an editor in it.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property var screenObj: null
    property real uiScale: 1

    focus: true

    // ===== the screen, and the card that stands for it =====
    readonly property real sw: root.screenObj ? root.screenObj.width : 1920
    readonly property real sh: root.screenObj ? root.screenObj.height : 1080

    // What the lock itself works out from the screen (LockCanvas.qml): `u` is 1 at 1080 p.
    readonly property real u: Math.max(0.55, root.sh / 1080) * root.uiScale
    function px(n) {
        return Math.round(n * root.u)
    }

    readonly property real pad: (EditMode.gap + EditMode.frameWidth) * root.uiScale
    readonly property real shelfPx: LockEditService.shelfHeight * root.uiScale
    readonly property var fit: EM.cardFit(root.width - root.pad * 2, root.height - root.shelfPx - root.pad * 2, root.sw, root.sh)
    // Card pixels per screen pixel.
    readonly property real k: root.fit.k
    readonly property real cardX: root.pad + root.fit.x
    readonly property real cardY: root.pad + root.fit.y

    readonly property real p: Math.max(0, Math.min(1, LockEditService.progress))

    // Where the card is RIGHT NOW. `progress` is 0 with the card as big as the screen and 1 with
    // it in its place; on the way in it goes a little past 1 (the pop), so it is not clamped
    // here. `cardX`, `cardY` and `k` above are where it ends up.
    readonly property real ps: Math.max(0, LockEditService.progress)
    readonly property real kNow: 1 + (root.k - 1) * root.ps
    readonly property real liveX: root.cardX * root.ps
    readonly property real liveY: root.cardY * root.ps
    readonly property real liveW: root.sw * root.kNow
    readonly property real liveH: root.sh * root.kNow

    // The wallpaper the lock would show on this monitor, and whether it is blurred.
    readonly property string wallpaperFile: WallpaperService.lockImagePathFor(root.screenObj ? root.screenObj.name : "")
    readonly property bool blurWallpaper: SettingsService.flag("lock.blur")

    // The widgets the lock has (the same map as LockCanvas.qml; a test checks they agree).
    readonly property var kinds: ({
        clock: clockWidget,
        date: dateWidget,
        user: userWidget,
        greeting: greetingWidget,
        weather: weatherWidget,
        sun: sunWidget,
        battery: batteryWidget,
        media: mediaWidget,
        lyrics: lyricsWidget,
        timer: timerWidget,
        notifications: notificationsWidget,
        event: eventWidget,
        todo: todoWidget,
        countdown: countdownWidget,
        text: textWidget,
        image: imageWidget
    })

    // The time the widgets show, kept current.
    readonly property date now: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // The screen-sized picture the widgets are in: pointer positions are mapped into it.
    readonly property Item view: cardView

    // Where a drag is lined up with something (screen pixels along that axis), or -1.
    property real guideX: -1
    property real guideY: -1

    // The keyboard stays with the stage, except while the words box has it.
    function takeFocus() {
        root.forceActiveFocus()
    }

    // The centres and sizes of everything but widget `skip` (-1: all of them), as the lists
    // of lines EditMath.snapAxis lines a widget up with.
    function linesFor(skip) {
        const xs = []
        const ys = []
        for (let i = 0; i < slots.count; i++) {
            const s = slots.itemAt(i)
            if (!s || i === skip || !s.visible)
                continue
            xs.push({ c: s.cx, d: s.drawnW })
            ys.push({ c: s.cy, d: s.drawnH })
        }
        // The password block, unless it is the one being moved.
        if (skip >= 0) {
            xs.push({ c: coreItem.cx, d: coreItem.drawnW })
            ys.push({ c: coreItem.cy, d: coreItem.drawnH })
        }
        return { xs: EM.linesOf(xs, root.sw), ys: EM.linesOf(ys, root.sh) }
    }

    // Is a window pixel over the card? And, if so, where on the screen is it?
    function overCard(x, y) {
        return x >= root.cardX && y >= root.cardY && x <= root.cardX + root.fit.w && y <= root.cardY + root.fit.h
    }

    // A key was let go over the card: put that widget there. (Over anything else: nothing.)
    function drop(kind, x, y) {
        if (!root.overCard(x, y))
            return
        LockEditService.add(kind, (x - root.cardX) / root.k / root.sw, (y - root.cardY) / root.k / root.sh)
    }

    // ===== keys =====
    Keys.onPressed: event => {
        if (shelf.typing) {
            // The words box has the keys; Esc gives them back.
            if (event.key === Qt.Key_Escape) {
                root.takeFocus()
                event.accepted = true
            }
            return
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0
        const sel = LockEditService.selected
        const step = shift ? 0.01 : 0.001
        const nudge = (dx, dy) => {
            if (sel !== "")
                LockEditService.nudge(sel, dx, dy)
            event.accepted = true
        }

        if (event.key === Qt.Key_Escape) {
            if (LockEditService.picking)
                return
            if (sel !== "")
                LockEditService.select("")
            else
                LockEditService.close()
            event.accepted = true
        } else if (ctrl && event.key === Qt.Key_Z) {
            if (shift)
                LockEditService.redo()
            else
                LockEditService.undo()
            event.accepted = true
        } else if (ctrl && event.key === Qt.Key_Y) {
            LockEditService.redo()
            event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
            LockEditService.selectNext(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Backtab) {
            LockEditService.selectNext(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (sel !== "" && sel !== "core")
                LockEditService.remove(sel)
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            nudge(-step, 0)
        } else if (event.key === Qt.Key_Right) {
            nudge(step, 0)
        } else if (event.key === Qt.Key_Up) {
            nudge(0, -step)
        } else if (event.key === Qt.Key_Down) {
            nudge(0, step)
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            if (sel !== "" && sel !== "core")
                LockEditService.stepScale(sel, 1, shift ? 0.25 : 0.05)
            event.accepted = true
        } else if (event.key === Qt.Key_Minus) {
            if (sel !== "" && sel !== "core")
                LockEditService.stepScale(sel, -1, shift ? 0.25 : 0.05)
            event.accepted = true
        }
    }

    Component.onCompleted: root.forceActiveFocus()

    // ===== the stage =====
    LockEditBackdrop {
        anchors.fill: parent
        uiScale: root.uiScale
        // Solid by the time the card has shrunk about half way.
        opacity: Math.min(1, root.p * 2.2)
    }

    // A click on the bare stage lets go of what is selected.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: {
            LockEditService.select("")
            root.takeFocus()
        }
        onWheel: wheel => wheel.accepted = true
    }

    // ===== the card =====
    Item {
        id: pop
        anchors.fill: parent

        // The frame's hard shadow: under the card.
        LockEditFrame {
            anchors.fill: parent
            drawRings: false
            uiScale: root.uiScale
            cardX: root.liveX
            cardY: root.liveY
            cardW: root.liveW
            cardH: root.liveH
            grow: root.ps
            opacity: Math.min(1, root.p * 1.6)
        }

        Item {
            x: root.liveX
            y: root.liveY
            width: root.liveW
            height: root.liveH
            clip: true
            // The picture is there from the first frames, so the card does not blink on over
            // the desktop; it is the shrinking that shows.
            opacity: Math.min(1, root.p * 5)

            // The whole screen, drawn at its own size and scaled down as one picture.
            Item {
                id: cardView
                width: root.sw
                height: root.sh
                scale: root.kNow
                transformOrigin: Item.TopLeft

                // Clicks on the bare card let go of the selection too.
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        LockEditService.select("")
                        root.takeFocus()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: LockPalette.fallbackTop }
                        GradientStop { position: 1.0; color: LockPalette.fallbackBottom }
                    }
                }

                Image {
                    id: wallpaper
                    anchors.fill: parent
                    visible: !root.blurWallpaper
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(Math.max(1, Math.round(root.sw / 2)), Math.max(1, Math.round(root.sh / 2)))
                    source: root.wallpaperFile !== "" ? ("file://" + root.wallpaperFile) : ""
                }

                MultiEffect {
                    anchors.fill: parent
                    source: wallpaper
                    visible: root.blurWallpaper && wallpaper.status === Image.Ready
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 40
                }

                // The same slate wash the lock puts over the picture.
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: LockPalette.scrimTop }
                        GradientStop { position: 0.5; color: LockPalette.scrimClear }
                        GradientStop { position: 1.0; color: LockPalette.scrimBottom }
                    }
                }

                // Where the password block can go, while it is being moved.
                Rectangle {
                    readonly property var lim: LM.coreLimits()
                    visible: coreItem.dragging
                    x: lim.xMin * root.sw - coreItem.width / 2
                    y: lim.yMin * root.sh - coreItem.height / 2
                    width: (lim.xMax - lim.xMin) * root.sw + coreItem.width
                    height: (lim.yMax - lim.yMin) * root.sh + coreItem.height
                    radius: 24 / root.k
                    color: Qt.rgba(root.mt.accentMint.r, root.mt.accentMint.g, root.mt.accentMint.b, 0.10)
                    border.width: 2 / root.k
                    border.color: root.mt.accentMint
                    z: 40
                }

                // The widgets.
                Repeater {
                    id: slots
                    model: LockEditService.board.items.length

                    LockEditSlot {
                        stage: root
                    }
                }

                LockEditCore {
                    id: coreItem
                    stage: root
                }

                // Guide lines while something snaps to them.
                Rectangle {
                    visible: root.guideX >= 0
                    x: root.guideX - width / 2
                    y: 0
                    width: 2 / root.k
                    height: root.sh
                    color: root.mt.accentMint
                    z: 60
                }

                Rectangle {
                    visible: root.guideY >= 0
                    x: 0
                    y: root.guideY - height / 2
                    width: root.sw
                    height: 2 / root.k
                    color: root.mt.accentMint
                    z: 60
                }
            }
        }

        // The frame's rings: OVER the card. They are what makes its corners round: the card is
        // a plain rectangle, and the ring is thick enough to hide its square corners, so only
        // the rounded hole shows the picture. (Drawn under the card, as it once was, the card's
        // square corners stuck out over the ring.)
        LockEditFrame {
            anchors.fill: parent
            drawShadow: false
            uiScale: root.uiScale
            cardX: root.liveX
            cardY: root.liveY
            cardW: root.liveW
            cardH: root.liveH
            grow: root.ps
            opacity: Math.min(1, root.p * 2)
        }

        // The lockscreen is not Custom yet: say so, with the key that makes it so.
        Pill {
            id: styleNote
            visible: !LockEditService.styleIsCustom
            // It waits for the card to be nearly in place.
            opacity: Math.max(0, Math.min(1, (root.p - 0.6) / 0.4))
            x: root.cardX + (root.fit.w - width) / 2
            y: root.cardY + 14 * root.uiScale
            width: noteRow.implicitWidth + 40
            height: 40
            scale: root.uiScale
            transformOrigin: Item.Top
            cornerRadius: 14
            ringWidth: 4
            shadowDy: 3
            fillColor: root.mt.pSurface

            Row {
                id: noteRow
                anchors.centerIn: parent
                spacing: 10

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "info"
                    size: 18
                    weight: 600
                    color: root.mt.pInk
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "The lockscreen style is not Custom, so this layout is not shown yet."
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.styleName: root.mt.fontStyleBold
                }

                Pill {
                    anchors.verticalCenter: parent.verticalCenter
                    width: useText.implicitWidth + 22
                    height: 26
                    cornerRadius: 9
                    ringWidth: 3
                    shadowDy: 3
                    pressed: useArea.pressed
                    fillGradient: Gradient {
                        GradientStop { position: 0.0; color: root.mt.accentMint }
                        GradientStop { position: 1.0; color: root.mt.accentCyan }
                    }

                    Text {
                        id: useText
                        anchors.centerIn: parent
                        text: "USE CUSTOM"
                        color: root.mt.colBorder
                        font.family: root.mt.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.ExtraBold
                        font.styleName: root.mt.fontStyleBold
                    }

                    MouseArea {
                        id: useArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LockEditService.useCustom()
                    }
                }
            }
        }
    }

    // ===== the shelf =====
    ScaleHost {
        id: shelfHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(root.shelfPx)
        factor: root.uiScale
        // It comes up from the bottom edge with the card.
        transform: Translate { y: (1 - root.p) * (root.shelfPx + 60 * root.uiScale) }

        LockEditShelf {
            id: shelf
            anchors.fill: parent
            onDropped: (kind, x, y) => root.drop(kind, x, y)
            onDone: LockEditService.close()
        }
    }

    // ===== the widget being dragged off the shelf =====
    Item {
        id: ghost
        visible: shelf.dragKind !== ""
        z: 100

        readonly property var info: LM.describe(shelf.dragKind)
        readonly property bool over: root.overCard(shelf.dragX, shelf.dragY)

        width: 120 * root.uiScale
        height: 70 * root.uiScale
        x: shelf.dragX - width / 2
        y: shelf.dragY - height / 2
        scale: ghost.over ? 1 : 0.8
        rotation: ghost.over ? 0 : -4
        opacity: ghost.over ? 0.95 : 0.6
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }

        Behavior on rotation {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Rectangle {
            x: 6
            y: 8
            width: parent.width
            height: parent.height
            radius: 14
            color: root.mt.pLineShadow
            opacity: 0.5
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.mt.pSurface
            border.width: ghost.over ? 3 : root.mt.borderWidth
            border.color: ghost.over ? root.mt.accentMint : root.mt.pLine

            Column {
                anchors.centerIn: parent
                spacing: 2

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: ghost.info ? ghost.info.icon : "widgets"
                    size: 26 * root.uiScale
                    weight: 600
                    color: root.mt.accentMint
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ghost.info ? ghost.info.title.toUpperCase() : ""
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.pixelSize: 10 * root.uiScale
                    font.weight: Font.ExtraBold
                    font.styleName: root.mt.fontStyleBold
                }
            }
        }
    }

    Component { id: clockWidget;        LockClockWidget {} }
    Component { id: dateWidget;         LockDateWidget {} }
    Component { id: userWidget;         LockUserWidget {} }
    Component { id: greetingWidget;     LockGreetingWidget {} }
    Component { id: weatherWidget;      LockWeatherWidget {} }
    Component { id: sunWidget;          LockSunWidget {} }
    Component { id: batteryWidget;      LockBatteryWidget {} }
    Component { id: mediaWidget;        LockMediaWidget {} }
    Component { id: lyricsWidget;       LockLyricsWidget {} }
    Component { id: timerWidget;        LockTimerWidget {} }
    Component { id: notificationsWidget; LockNotificationsWidget {} }
    Component { id: eventWidget;        LockEventWidget {} }
    Component { id: todoWidget;         LockTodoWidget {} }
    Component { id: countdownWidget;    LockCountdownWidget {} }
    Component { id: textWidget;         LockTextWidget {} }
    Component { id: imageWidget;        LockImageWidget {} }
}
