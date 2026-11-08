import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// The lockscreen editor's stage: what is behind the card. The same dark navy with faint mint
// and cyan diamonds as Edit Desktop's (EditBackdrop.qml), so the two modes feel like one
// place. The diamond field is painted once per size, and only while the editor is open.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property real uiScale: 1

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.darker(root.mt.colBorder, 2.1) }
            GradientStop { position: 1.0; color: Qt.darker(root.mt.colBorder, 2.9) }
        }
    }

    Canvas {
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width
            const h = height
            if (w < 32 || h < 32)
                return

            const step = 64 * root.uiScale
            const r = 7 * root.uiScale
            let row = 0
            for (let y = step / 2; y < h + step; y += step * 0.75) {
                const off = (row % 2) * step / 2
                for (let x = off; x < w + step; x += step) {
                    ctx.globalAlpha = 0.07 + ((row * 7 + Math.round(x / step) * 3) % 5) * 0.012
                    ctx.fillStyle = ((row + Math.round(x / step)) % 2 === 0) ? root.mt.accentMint : root.mt.accentCyan
                    ctx.beginPath()
                    ctx.moveTo(x, y - r)
                    ctx.lineTo(x + r, y)
                    ctx.lineTo(x, y + r)
                    ctx.lineTo(x - r, y)
                    ctx.closePath()
                    ctx.fill()
                }
                row++
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
