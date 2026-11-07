// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// A full-area "working on it" overlay: the spinner with a small caption and an
// optional detail line (which chapter, which episode). Fades in and out with
// `active`; set `color` for the backdrop (transparent-ish to keep what's
// behind in view).
Rectangle {
    id: root

    property bool active: false
    property string label: "loading"
    property string detail: ""
    property string bodyFont: Theme.fontFamily
    property int spinnerSize: 34
    property color textColor: Colors.on_surface_variant
    property color arcColor: Colors.primary

    color: Colors.background
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Swallow clicks so nothing behind reacts while this is up.
    MouseArea { anchors.fill: parent; enabled: root.active }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Spinner {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.spinnerSize
            border.width: 2.5
            arcColor: root.arcColor
            duration: 1000
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.label
                color: root.textColor
                font.family: root.bodyFont
                font.pixelSize: 12
                font.letterSpacing: 1.5
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
                opacity: 0.85
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.detail.length > 0
                width: Math.min(implicitWidth, 280)
                horizontalAlignment: Text.AlignHCenter
                text: root.detail
                color: root.textColor
                font.family: root.bodyFont
                font.pixelSize: 11
                elide: Text.ElideRight
                opacity: 0.45
            }
        }
    }
}
