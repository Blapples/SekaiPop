import QtQuick
import qs.services

// Which look a monitor's lockscreen wears: the Project Sekai gacha screen
// (LockSurface.qml, the default), the Calendar poster (LockCalendar.qml) or the Custom
// screen you arrange yourself (LockCanvas.qml). Picked in
// Settings -> General -> Launcher & lock -> Lockscreen style, or
//   qs -c sekaipop ipc call options set lock.style calendar     (gacha | calendar | custom)
//
// Lockscreen.qml (the real lock surface) and LockRing.qml (its copy that plays the
// transition) both use this, so they always show the same look. Only the chosen look
// is built: the other costs nothing, not even its animations.
//
// It gives both looks the same four things (the shared LockContext, the monitor's
// scale and name, and `wallpaperReady`, which LockRing waits for) and nothing else.
Item {
    id: root

    // The shared LockContext.
    required property var context
    property real uiScale: 1
    property string screenName: ""

    // False = the look is not built at all. LockRing.qml keeps one of these per monitor for the
    // whole life of the shell (to play the lock / unlock transition), and it used to hold a full
    // lockscreen (the 40 KB look, the wallpaper decode, its models and timers) the whole time
    // while nothing was locked. It now sets this to false when LockState is idle and the look is
    // destroyed. Default true: the real lock surface (Lockscreen.qml) always wants it.
    property bool live: true

    readonly property bool calendar: SettingsService.get("lock.style") === "calendar"

    // The Custom look (LockCanvas.qml): the widgets you placed and the password block. Its
    // layout (LockCanvasService) is read from disk a moment after the shell starts, so this
    // host asks for it as soon as Custom is the style, long before any lock: the first lock
    // after a restart then already has your layout instead of the first one.
    readonly property bool custom: SettingsService.get("lock.style") === "custom"
    readonly property bool canvasLoaded: root.custom ? LockCanvasService.loaded : true

    // The Calendar look's picture map (a tiny ImageMagick read, LockCropService) used to be
    // asked for the moment the look was built, which was at shell start, long before any
    // lock. The look is only built while locking now, so this host asks for it itself when
    // the wallpaper (or the style / crop setting) changes. It is cheap and de-duplicated;
    // without it the first lock after a wallpaper change would wait for the read.
    readonly property string warmFile: root.calendar ? WallpaperService.lockImagePathFor(root.screenName) : ""
    readonly property bool warmAuto: SettingsService.get("lock.crop") !== "fixed"
    function warmCrop() {
        if (root.calendar && root.warmAuto && root.warmFile !== "")
            LockCropService.request(root.warmFile)
    }
    onWarmFileChanged: root.warmCrop()
    onWarmAutoChanged: root.warmCrop()
    Component.onCompleted: root.warmCrop()

    // False while the picture is still being made (and until the look exists).
    readonly property bool wallpaperReady: face.item ? face.item.wallpaperReady : false

    Loader {
        id: face
        anchors.fill: parent
        active: root.live
        sourceComponent: root.custom ? customLook : (root.calendar ? calendarLook : gachaLook)
    }

    Component {
        id: gachaLook

        LockSurface {
            context: root.context
            uiScale: root.uiScale
            screenName: root.screenName
        }
    }

    Component {
        id: calendarLook

        LockCalendar {
            context: root.context
            uiScale: root.uiScale
            screenName: root.screenName
        }
    }

    Component {
        id: customLook

        LockCanvas {
            context: root.context
            uiScale: root.uiScale
            screenName: root.screenName
        }
    }
}
