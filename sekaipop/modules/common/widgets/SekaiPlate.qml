import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.modules.common

// The header plate every bar popup (Weather, Calendar, Battery, Discord) opens
// with: a gradient slab on the shell's Pill (outline, ring, hard shadow) with
// a printed halftone in one corner and two slanted bands of stage light, the
// look the Discord panel's blurple plate already had, made reusable so the four
// cards read as one family. Things declared inside land on top of the plate
// and are NOT clipped, so a sticker numeral or a tilted stamp can break out
// over the plate's edge. Their coordinates are the plate's own: (0, 0) is its
// top-left corner and the face is `height - Theme.shadowOffset` tall.
//
//   SekaiPlate {
//       width: 304; height: 104
//       colorTop: Theme.accentMint; colorBottom: Theme.accentCyan
//       StickerText { x: 12; y: 0; text: "24"; pixelSize: 60 }
//   }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property color colorTop: mt.accentMint
    property color colorBottom: mt.accentCyan
    property real cornerRadius: 16
    // Outline + the white line (Theme.whiteLine): the same as every block's.
    property real ringWidth: mt.borderWidth + mt.whiteLine
    // The halftone and the light bands. Dark dots / white bands suit a light
    // plate; a dark plate wants the other way round (set dotColor).
    property color dotColor: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.16)
    property color bandColor: Qt.rgba(1, 1, 1, 0.22)
    property string dotCorner: "tr"
    property real dotSpacing: 14
    // False while the plate's width is being animated: the halftone is hidden and not painted
    // again for every width (see DotField.live), then fades back in at the final one.
    property bool dotsLive: true
    property bool pressed: false

    // Big sticker numerals on the plate: a DARK fill inside the white ring. A
    // white fill merged into the white ring and the digits lost their shapes on
    // the pale plate. Used by every popup's number / month.
    readonly property color numberFill: Qt.darker(mt.colBorder, 1.8)
    readonly property color numberRing: "#ffffff"

    // The part of the plate above its hard shadow.
    readonly property real faceHeight: root.height - mt.shadowOffset

    default property alias content: layer.data

    implicitHeight: 100 + mt.shadowOffset

    Gradient {
        id: plateGradient
        GradientStop { position: 0.0; color: root.colorTop }
        GradientStop { position: 1.0; color: root.colorBottom }
    }

    Pill {
        id: pill
        anchors.fill: parent
        cornerRadius: root.cornerRadius
        ringWidth: root.ringWidth
        fillGradient: plateGradient
        pressed: root.pressed

        ClippingRectangle {
            anchors.fill: parent
            radius: Math.max(0, root.cornerRadius - root.ringWidth)
            color: "transparent"

            DotField {
                anchors.fill: parent
                corner: root.dotCorner
                spacing: root.dotSpacing
                maxRadius: 3.4
                reach: 0.95
                dotColor: root.dotColor
                live: root.dotsLive
                // 0.01, not 0: an item at opacity 0 is skipped, and it has to be painted at the end
                opacity: root.dotsLive ? 1 : 0.01
                Behavior on opacity { NumberAnimation { duration: root.dotsLive ? 220 : 0 } }
            }
            Slant {
                x: parent.width * 0.56
                y: -8
                width: 46
                height: parent.height + 16
                skew: 0.22
                radius: 0
                color: root.bandColor
            }
            Slant {
                x: parent.width * 0.56 + 56
                y: -8
                width: 20
                height: parent.height + 16
                skew: 0.22
                radius: 0
                color: root.bandColor
            }
        }
    }

    Item {
        id: layer
        width: root.width
        height: root.faceHeight
    }
}
