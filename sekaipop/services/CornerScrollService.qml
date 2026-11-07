pragma Singleton
import QtQuick
import Quickshell

// Scroll the wheel (or two fingers on a touchpad) with the pointer pushed into the top-left
// or the top-right corner of a screen to change the volume or the brightness (issue #141,
// the way end-4's dots do it). The corner windows are in
// modules/sekai/screenCorners/CornerScroll.qml; this holds what they and the bar share.
//
// Settings -> General -> Screen corners ("corners.scroll", off by default: the strips take
// the top pixel rows next to the corners, where a maximized window's close button sits).
//   Left corner:  volume       Right corner:  brightness
// ("corners.swap" puts them the other way round.) Up = more, down = less, 5 % a step, and the
// on-screen display shows what changed.
Singleton {
    id: root

    // Nothing in Game Mode (a game gets every pixel of the screen, like the bar's own input).
    readonly property bool enabled: SettingsService.flag("corners.scroll") && !GameModeService.enabled
    readonly property bool swapped: SettingsService.flag("corners.swap")

    // The strip along the top edge of each corner, in px. Same idea as the Quick Panel's hot
    // edge (a few px deep): the pointer pushed against the top of the screen is always in it.
    readonly property real zoneWidth: 140
    readonly property real zoneHeight: 4

    // What a corner changes: "volume" | "brightness".
    function kindFor(side) {
        const left = side === "left"
        return (left !== root.swapped) ? "volume" : "brightness"
    }

    // One notch (dir = 1 up, -1 down).
    function step(side, dir) {
        if (root.kindFor(side) === "volume") {
            if (dir > 0)
                OSDSource.volumeUp()
            else
                OSDSource.volumeDown()
        } else {
            if (dir > 0)
                OSDSource.brightnessUp()
            else
                OSDSource.brightnessDown()
        }
    }
}
