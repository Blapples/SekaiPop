import Quickshell
import QtQuick
import QtQuick.Effects
import qs.services
import qs.modules.common
import "../../common/functions/LockCanvasModel.js" as LM

// The Custom lockscreen: your wallpaper, the widgets you placed (clock, date, weather ...),
// and the password block (LockCore.qml). Which widgets, where and with what options is the
// board LockCanvasService keeps (Settings -> General -> Launcher & lock -> Lockscreen style
// -> Custom); this only draws it. LockHost.qml builds it, like the Gacha and Calendar looks,
// and gives it the same four things.
//
// What keeps it safe (docs/LOCKCANVAS.md):
//   - The board is checked before it gets here (LockCanvasModel.js): known widgets only,
//     every number in range. A widget is a name that maps to a QML file below; nothing in
//     the saved layout is ever run or loaded as code.
//   - The password block is built here, always, on top of everything, and kept on screen.
//   - THIS Item catches every key, like the other looks: the password is typed here and
//     goes to the shared LockContext. No widget has a text field or takes the focus, so a
//     key can not land in one.
//   - A widget that fails to load is skipped (its Loader gives nothing), the rest are drawn.
//
// Everything is sized off the screen's height (`u` = 1 at 1080 px tall), times the monitor's
// own scale (`uiScale`), so a layout looks the same on every screen.
Item {
    id: root

    // The shared LockContext.
    required property var context
    property real uiScale: 1
    // Which monitor this is: its wallpaper, and its board (else the shared one).
    property string screenName: ""

    readonly property bool blurWallpaper: SettingsService.flag("lock.blur")
    readonly property string wallpaperFile: WallpaperService.lockImagePathFor(root.screenName)

    readonly property real u: Math.max(0.55, root.height / 1080) * root.uiScale
    function px(n) {
        return Math.round(n * root.u)
    }

    // False while the wallpaper is still being decoded. LockRing.qml waits for it so the
    // transition never runs over a half-loaded picture.
    readonly property bool wallpaperReady: wallpaper.status !== Image.Loading

    // This monitor's board: { core: { x, y }, items: [ { uid, kind, x, y, scale, options } ] }.
    readonly property var board: LockCanvasService.boardFor(root.screenName)

    // The only widgets there are. A saved name that is not here draws nothing.
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

    focus: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.context.tryUnlock()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.context.selectAll()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Delete) {
            if (root.context.allSelected)
                root.context.backspace()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Backspace) {
            // Ctrl+Backspace wipes the lot, plain Backspace takes one off.
            if (event.modifiers & Qt.ControlModifier)
                root.context.clearText()
            else
                root.context.backspace()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Escape
            || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) {
            root.context.clearText()
            event.accepted = true
            return
        }
        // Anything that types a character. Control combinations arrive
        // with a control character as their text (< 32), so this leaves
        // them out; AltGr characters (@, €, ...) come through as normal.
        const t = event.text
        if (t.length > 0 && t.charCodeAt(0) >= 32 && t.charCodeAt(0) !== 127) {
            root.context.typeText(t)
            event.accepted = true
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus()
    }

    // Anywhere you click puts the keyboard back on this monitor. Under the widgets, so the
    // media keys get their clicks.
    MouseArea {
        anchors.fill: parent
        onPressed: root.forceActiveFocus()
    }

    Connections {
        target: root.context
        function onFocusRequested() {
            root.forceActiveFocus()
        }
        function onResumed() {
            // Re-read wall time now; a minute timer can retain its pre-sleep delay.
            // Re-enabling also schedules the next normal minute boundary.
            clock.enabled = false
            clock.enabled = true
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Live data for the widgets that need it. Both are passive (UPower / MPRIS, nothing
    // polls), and they only exist while locked.
    BatterySource {
        id: battery
    }

    MediaSource {
        id: media
    }

    // ===== background =====
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: LockPalette.fallbackTop }
            GradientStop { position: 1.0; color: LockPalette.fallbackBottom }
        }
    }

    // The wallpaper, decoded at screen size.
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: !root.blurWallpaper
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, root.width), Math.max(1, root.height))
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

    // A whisper of slate over the whole picture, and more towards the bottom so the
    // password block always reads.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: LockPalette.scrimTop }
            GradientStop { position: 0.5; color: LockPalette.scrimClear }
            GradientStop { position: 1.0; color: LockPalette.scrimBottom }
        }
    }

    // ===== the widgets =====
    Repeater {
        model: root.board.items

        delegate: Item {
            id: slot

            required property var modelData
            readonly property var spec: slot.modelData

            // The widget's own size; it is drawn scaled around its centre, and put where
            // the board says, pulled back so all of it stays on the screen.
            width: ld.item ? ld.item.implicitWidth : 0
            height: ld.item ? ld.item.implicitHeight : 0
            scale: slot.spec.scale
            transformOrigin: Item.Center
            x: LM.placeAxis(slot.spec.x, slot.width, slot.spec.scale, root.width)
            y: LM.placeAxis(slot.spec.y, slot.height, slot.spec.scale, root.height)
            z: 1
            visible: slot.width > 0 && slot.height > 0

            Loader {
                id: ld
                sourceComponent: root.kinds[slot.spec.kind]

                onLoaded: {
                    ld.item.options = Qt.binding(() => slot.spec.options)
                    ld.item.u = Qt.binding(() => root.u)
                    ld.item.now = Qt.binding(() => clock.date)
                    ld.item.media = media
                    ld.item.battery = battery
                    ld.item.context = root.context
                }
            }
        }
    }

    // ===== the password block: always, on top of everything =====
    LockCore {
        id: core
        z: 100
        context: root.context
        overlay: root
        u: root.u
        x: LM.placeAxis(root.board.core.x, core.width, 1, root.width)
        y: LM.placeAxis(root.board.core.y, core.height, 1, root.height)
        onRefocus: root.forceActiveFocus()
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
