import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The weather card at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): the sky in a window. ONE rounded key whose face is the sky (pale by day, the
// shell's dark navy by night) with the weather drawn big in its upper left (the shell's own Solar icons) and the
// temperature as a sticker numeral in its lower right, so the two sit on a diagonal and
// nothing overlaps. No place, no forecast, no backdrop.
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
    // into the glyph. The unit is a little under half the number, hung from its top like a
    // degree sign.
    readonly property int numSize: root.num.length <= 2 ? 46 : (root.num.length === 3 ? 38 : 30)
    readonly property int unitSize: Math.round(root.numSize * 0.4)

    readonly property color skyInk: root.night ? mt.accentMint : mt.colBorder
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
                GradientStop { position: 1.0; color: root.night ? mt.chipFill : Qt.tint(mt.pSurface, Qt.rgba(mt.accentMint.r, mt.accentMint.g, mt.accentMint.b, 0.55)) }
            }

            transformOrigin: Item.Center
            rotation: root.hover && !root.pressed ? -2 : 0

            Behavior on rotation {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }

            // The weather, big, upper left. Drawn with the shell's own icons (MaterialIcon, the
            // Solar set in the style chosen in Settings), like the bar and the rest of the shell.
            MaterialIcon {
                id: glyph
                visible: root.icon !== ""
                x: 8
                y: 6
                size: 62
                name: root.icon
                color: root.skyInk
                transformOrigin: Item.Center
                rotation: root.hover && !root.pressed ? 14 : 0

                Behavior on rotation {
                    NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                }
            }

            // The temperature, lower right.
            Item {
                id: group
                width: tempNum.width + (root.unit !== "" ? tempUnit.width - 6 : 0)
                height: tempNum.height
                x: parent.width - group.width - 6
                y: parent.height - group.height + 2

                StickerText {
                    id: tempNum
                    text: root.num
                    pixelSize: root.numSize
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }

                StickerText {
                    id: tempUnit
                    visible: root.unit !== ""
                    x: tempNum.width - 6
                    y: Math.round(root.numSize * 0.16)
                    text: root.unit
                    pixelSize: root.unitSize
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }
            }
        }
    }
}
