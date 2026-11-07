import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// Centred "nothing here yet" placeholder: a sticker diamond with a glyph on it, a headline,
// a hint line. The diamond is the shell's key shape (outlined, ring, hard shadow).
Column {
    id: root

    property string glyph: "⊡"
    property string title: ""
    property string subtitle: ""
    // Kept for the call sites that set them; the shell's own font is used.
    property string displayFont: ""
    property string bodyFont: ""

    anchors.centerIn: parent
    spacing: 16

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 84
        height: 84

        Rectangle {
            x: 14 + 4; y: 14 + 4
            width: 56; height: 56; radius: 18; rotation: 45
            color: Theme.lineShadow
            antialiasing: true
        }

        Rectangle {
            id: face
            x: 14; y: 14
            width: 56; height: 56; radius: 18; rotation: 45
            color: Theme.ringWhite
            border.width: 3
            border.color: Theme.line
            antialiasing: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 12
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.accentMint }
                    GradientStop { position: 1.0; color: Theme.accentCyan }
                }
            }
        }

        Text {
            anchors.centerIn: face
            text: root.glyph
            font.pixelSize: 24
            font.weight: Font.ExtraBold
            color: Theme.colBorder
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.title
        color: Theme.ink
        font.family: Theme.fontFamily
        font.pixelSize: 17
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.subtitle
        color: Theme.inkSub
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
