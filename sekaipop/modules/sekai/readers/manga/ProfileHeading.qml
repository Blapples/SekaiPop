import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// A section's heading with its one-line hint, for the sections of the profile page.
//
//   ProfileHeading { title: "Reading now"; hint: "From your AniList \u00b7 39" }
Column {
    property string title: ""
    property string hint: ""
    spacing: 2

    Text {
        text: parent.title
        color: Theme.ink
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }

    Text {
        visible: parent.hint.length > 0
        text: parent.hint
        color: Theme.inkSub
        font.family: Theme.fontFamily
        font.pixelSize: ReaderType.sizeCaption
        font.weight: ReaderType.weightBody
        font.styleName: ReaderType.styleBody
    }
}
