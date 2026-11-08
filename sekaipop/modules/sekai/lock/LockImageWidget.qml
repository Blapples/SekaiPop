import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A picture of yours: a photo, a sticker. Options: `path` (an absolute path to a picture;
// LockCanvasModel.js only lets a plain picture path through) and `shape` (rounded | circle |
// square). A square, scaled like any widget. Nothing is drawn for no picture or one that
// can not be read (the editor shows an empty frame to drop one on).
LockWidget {
    id: root

    readonly property string path: String(root.opt("path", ""))
    readonly property string shape: String(root.opt("shape", "rounded"))
    readonly property bool loaded: picture.status === Image.Ready
    readonly property bool shown: root.loaded || root.preview
    readonly property real side: root.px(320)
    readonly property real corner: root.shape === "circle" ? root.side / 2 : (root.shape === "square" ? 0 : root.px(34))

    implicitWidth: root.shown ? root.side : 0
    implicitHeight: root.shown ? root.side : 0

    RoundClip {
        visible: root.shown
        width: root.side
        height: root.side
        radii: [root.corner, root.corner, root.corner, root.corner]
        color: root.loaded ? "transparent" : LockPalette.cap

        Image {
            id: picture
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(Math.round(root.side * 2), Math.round(root.side * 2))
            source: root.path !== "" ? "file://" + root.path : ""
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: !root.loaded
            name: "add_photo_alternate"
            size: root.px(80)
            weight: 500
            color: LockPalette.lavenderText
        }
    }
}
