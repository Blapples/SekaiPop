import QtQuick
import Quickshell
import QtQuick.Controls.impl
import qs.modules.common
import "../functions/IconMap.js" as IconMap

// One icon, drawn from the Solar Icon Set (assets/icons: `bold` and `outline`
// folders, SVG).
//
//   MaterialIcon { name: "wifi_off"; size: 24 }
//
// `name` is still the Material Symbols name the shell has always used, so no
// page had to change: IconMap.js says which Solar file stands for it (a name
// that is already a Solar file name, with _ for -, needs no entry there). It's
// a vector image, so it stays crisp at any size and under the Quick Panel's
// tilt.
//
// `fill` picks the file: 0 = the style chosen in Settings (outline, broken, line
// duotone or bold duotone), 1 = bold (the Solar "Bold" set plays the part of
// FILL 1). If a name has no file in that style it tries outline, then bold, and
// a name with no Solar icon at all is still written as text in the
// "Material Symbols Rounded" font, as before.
//
// Colour is `color` (the mode's ink by default: navy in light mode, pale in dark), so hover / muted /
// on-a-dark-pill looks are just a colour, not a second asset.
//
// The look of every icon in the shell is set in one place, Theme.qml
// (iconFill); `fill` here overrides it for a single icon. `weight` is only
// used by the font fallback (the Solar files have one weight each).
Text {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string name: ""
    property real size: 24
    property real fill: mt.iconFill        // 0 outline .. 1 filled
    property real weight: mt.iconWeight    // 100 .. 700

    // In the Capsule bar the chips are 21 px tall, so its icons are drawn at most
    // 16 px (the layouts follow the width, so nothing needs to know).
    readonly property real drawSize: mt.capsuleFor(root) ? Math.min(size, 16) : size

    readonly property bool filled: root.fill >= 0.5
    readonly property var solarFiles: IconMap.candidates(root.name, root.filled, mt.iconStyle)

    // Which of solarFiles is being tried; one past the last = none exists.
    property int attempt: 0
    onSolarFilesChanged: root.attempt = 0

    width: drawSize
    height: drawSize
    text: root.attempt >= root.solarFiles.length ? name : ""
    color: mt.classicFor(root) ? mt.pInk : mt.ink
    // SVG icons already fit their bounds. Clipping their image child can hide
    // them during the phone animation; retain clipping for the font fallback.
    clip: root.text !== ""

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    font.family: mt.iconFont
    font.pixelSize: drawSize
    font.hintingPreference: Font.PreferFullHinting
    font.variableAxes: ({
        "FILL": root.fill,
        "wght": root.weight,
        // The font's own optical-size axis only runs 20..48
        "opsz": Math.max(20, Math.min(48, root.drawSize)),
        "GRAD": 0
    })

    ColorImage {
        readonly property real face: Math.round(root.drawSize * 0.88)
        x: Math.floor((root.width - face) / 2)
        y: Math.floor((root.height - face) / 2)
        width: face
        height: face
        visible: root.attempt < root.solarFiles.length && root.name !== ""
        color: root.color
        fillMode: Image.PreserveAspectFit
        mipmap: true
        sourceSize: Qt.size(face * (Math.ceil(Screen.devicePixelRatio) + 1), face * (Math.ceil(Screen.devicePixelRatio) + 1))
        source: root.name === "" || root.attempt >= root.solarFiles.length ? ""
            : "file://" + Directories.asset(root.solarFiles[root.attempt])
        onStatusChanged: {
            if (status === Image.Error && root.attempt < root.solarFiles.length)
                Qt.callLater(() => root.attempt++)
        }
    }
}
