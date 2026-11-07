import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// A key of the phone mirror, drawn like one of the bar's workspace badges (WorkspaceBadges.qml):
// a Pill with the 8 px white ring, the hard shadow straight down, cyan at rest and one of the
// five pastels while the pointer is over it, which also swells it a little, the way the
// active workspace's badge swells. Pressing it pushes the cap into its shadow (Pill.pressed).
//
// A key with a glyph is round (36 x 36, like a badge). With a `label` too, it is a pill as wide
// as its text.
//
//   MirrorBadge { unit: 1; icon: "arrow_back"; hot: mt.attributeColors[1]; onClicked: ... }
//
// `unit` is the shell's UI scale on this monitor: the badge is drawn at its design size and
// scaled, and takes up the scaled size in a layout.
Item {
    id: root

    readonly property var mt: Theme.of(QsWindow.window)

    property string icon: ""
    property string label: ""
    property real unit: 1
    // The colour it takes while the pointer is over it.
    property color hot: mt.attributeColors[0]
    // A key that is "on" keeps its hot colour.
    property bool lit: false

    signal clicked()

    readonly property real badgeSize: 36
    readonly property real designWidth: root.label === ""
        ? root.badgeSize
        : Math.max(root.badgeSize, content.implicitWidth + 26)

    implicitWidth: Math.round(root.designWidth * root.unit)
    implicitHeight: Math.round((root.badgeSize + mt.shadowOffset) * root.unit)
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1 : 0.4

    Pill {
        id: pill
        width: root.designWidth
        height: root.badgeSize + mt.shadowOffset
        anchors.centerIn: parent
        transformOrigin: Item.Center
        // Laid out at its design size and scaled about its middle to the size the layout was
        // given; the swell on hover is on top of that.
        scale: root.unit * (area.containsMouse || root.lit ? 1.14 : 1)

        cornerRadius: mt.radiusBadge
        ringWidth: 8
        fillColor: (area.containsMouse || root.lit) ? root.hot : mt.accentCyan
        pressed: area.pressed

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 2.2
            }
        }

        Behavior on fillColor {
            ColorAnimation { duration: 150 }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 4

            MaterialIcon {
                visible: root.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon
                size: 20
                color: mt.colBorder
            }

            Text {
                visible: root.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: mt.colBorder
                font.family: mt.fontFamily
                font.styleName: mt.fontStyleBold
                font.pixelSize: 14
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
