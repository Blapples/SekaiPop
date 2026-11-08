import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The weather card at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): the sky in a window. ONE rounded key. The temperature is the hero, a big sticker numeral
// in the lower left with its degree sign hung from the top of the numeral and the unit letter under
// it. The weather is a round "sky" chip in the upper right: a disc with the shell's own ring and
// hard shadow, mint by day and the shell's navy at night, with the glyph drawn dark on it (mint at
// night), so it is always readable, whatever the wallpaper or the palette. The key behind is the
// sky: pale at the top and a little colour toward the ground, navy at night.
//
// It sinks into its hard shadow while pressed. Point at it and the key tips, and the weather
// glyph turns a little (the sun spins up). The numeral hops when the reading changes.
//
//   WeatherTile {
//       width: card.contentW; height: card.contentH
//       num: win.hasData ? win.temp.num : "--"
//       unit: win.hasData ? win.temp.unit : ""
//       icon: win.hasData ? wx.iconName : ""
//       hover: dragArea.containsMouse
//       pressed: dragArea.pressed
//   }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string num: "--"
    property string unit: ""
    // OpenMeteo's icon name (wx.iconName); empty = no glyph.
    property string icon: ""
    property bool hover: false
    property bool pressed: false

    // After dark the key turns navy (the glyph and the numeral turn light with it).
    readonly property bool night: root.icon.indexOf("night") >= 0

    // Two characters are the big size; "100", "-12" and "21.5" step down so they never run
    // into the glyph.
    readonly property int numSize: root.num.length <= 2 ? 48 : (root.num.length === 3 ? 38 : 30)

    // The unit "°C" is two things: the degree sign (hung from the top of the numeral, like a
    // superscript) and the letter (a smaller sticker under it).
    readonly property bool hasDegree: root.unit.length > 0 && root.unit.charAt(0) === "\u00b0"
    readonly property string degreeText: root.hasDegree ? "\u00b0" : ""
    readonly property string letterText: root.hasDegree ? root.unit.slice(1) : root.unit

    // The sticker numerals' ink: dark in a white ring by day, light in a white ring by night.
    readonly property color numberFill: root.night ? mt.accentMint : Qt.darker(mt.colBorder, 1.8)
    readonly property color numberRing: "#ffffff"

    TinyFoot {
        id: foot
        anchors.fill: parent

        Pill {
            id: key
            width: foot.capW
            height: foot.capH + foot.shadowDy
            cornerRadius: 30
            ringWidth: mt.borderWidth + mt.whiteLine
            pressed: root.pressed

            // The sky: paper at the top, a little colour toward the ground; navy at night.
            fillColor: root.night ? mt.chipFill : mt.pSurface
            fillGradient: Gradient {
                GradientStop { position: 0.0; color: root.night ? Qt.lighter(mt.chipFill, 1.12) : mt.pSurface }
                GradientStop { position: 1.0; color: root.night ? mt.chipFill : Qt.tint(mt.pSurface, Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.32)) }
            }

            transformOrigin: Item.Center
            rotation: root.hover && !root.pressed ? -2 : 0

            Behavior on rotation {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }

            // The sky chip, upper right: a disc with the weather on it.
            Pill {
                id: sky
                visible: root.icon !== ""
                width: 46
                height: 46 + 3
                x: parent.width - width - 8
                y: 8
                shadowDy: 3
                cornerRadius: 23
                ringWidth: mt.borderWidth + mt.whiteLine
                fillColor: root.night ? mt.chipFill : mt.accentMint

                MaterialIcon {
                    id: glyph
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    name: root.icon
                    size: 28
                    color: root.night ? mt.accentMint : mt.colBorder
                    transformOrigin: Item.Center
                    rotation: root.hover && !root.pressed ? 14 : 0

                    Behavior on rotation {
                        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }
                }
            }

            // The temperature, lower left: the numeral, the degree sign on its shoulder and the
            // unit letter under that.
            Item {
                id: group
                width: tempNum.width + (root.unit !== "" ? Math.max(degree.width, letter.width) - 8 : 0)
                height: tempNum.height
                x: 6
                y: parent.height - group.height + 2

                StickerText {
                    id: tempNum
                    text: root.num
                    pixelSize: root.numSize
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }

                StickerText {
                    id: degree
                    visible: root.degreeText !== ""
                    x: tempNum.width - 8
                    y: Math.round(root.numSize * 0.1)
                    text: root.degreeText
                    pixelSize: Math.round(root.numSize * 0.5)
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }

                StickerText {
                    id: letter
                    visible: root.letterText !== ""
                    x: tempNum.width - 8
                    y: root.degreeText !== "" ? Math.round(root.numSize * 0.1) + Math.round(root.numSize * 0.36) : Math.round(root.numSize * 0.16)
                    text: root.letterText
                    pixelSize: Math.round(root.numSize * 0.34)
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }
            }
        }
    }
}
