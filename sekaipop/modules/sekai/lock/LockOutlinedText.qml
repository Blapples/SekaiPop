import QtQuick
import qs.modules.common

// Big white type with a thick coloured outline, the lockscreen's way of writing the time
// (the same construction as the Gacha look's OutlinedText). Fourteen copies in the outline
// colour around one in the front colour.
Item {
    id: ot

    property string text: ""
    property int pixelSize: 40
    property color color: "white"
    property color outlineColor: LockPalette.periwinkle
    property int outline: 4

    implicitWidth: face.implicitWidth + ot.outline * 2
    implicitHeight: face.implicitHeight + ot.outline * 2

    Repeater {
        model: 14
        delegate: Text {
            required property int index
            x: ot.outline + Math.cos(index * Math.PI / 7) * ot.outline
            y: ot.outline + Math.sin(index * Math.PI / 7) * ot.outline
            text: ot.text
            color: ot.outlineColor
            font.family: Theme.fontFamily
            font.pixelSize: ot.pixelSize
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }

    Text {
        id: face
        x: ot.outline
        y: ot.outline
        text: ot.text
        color: ot.color
        font.family: Theme.fontFamily
        font.pixelSize: ot.pixelSize
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }
}
