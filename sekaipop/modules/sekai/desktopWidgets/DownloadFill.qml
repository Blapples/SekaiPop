import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The colour that rises inside the Downloader's key as a file comes in (DownloaderTile.qml,
// DownloaderWidget.qml): a body of mint fading to cyan from the bottom, with a bright line on
// its top edge, clipped to the key's rounded inside. The same look as WaterFill.qml, so the
// two widgets match, and it follows matugen like everything else.
//
//   DownloadFill {
//       anchors.fill: parent
//       radius: key.cornerRadius - key.ringWidth     // the key's inner corner radius
//       level: 0.6                                   // 0..1 (a little more is fine: the overshoot)
//   }
RoundClip {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property real level: 0
    property real radius: 20

    radii: [root.radius, root.radius, root.radius, root.radius]

    Rectangle {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.height * Math.max(0, Math.min(1.08, root.level))

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.mt.accentMint.r, root.mt.accentMint.g, root.mt.accentMint.b, 0.86) }
            GradientStop { position: 1.0; color: Qt.rgba(root.mt.accentCyan.r, root.mt.accentCyan.g, root.mt.accentCyan.b, 0.7) }
        }

        // The top edge: a bright line.
        Rectangle {
            visible: body.height > 5
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            color: Qt.rgba(1, 1, 1, 0.7)
        }
    }
}
