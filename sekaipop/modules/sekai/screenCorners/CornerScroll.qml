import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services

// The scroll corners (services/CornerScrollService.qml): a thin strip along the top edge at
// each end of every screen. Scrolling over the left one changes the volume, over the right
// one the brightness (swappable in Settings). They take nothing but the wheel: no click,
// no hover. Nothing exists while the setting is off.
//
// With the bar on the top edge (or the left / right one) the strips lie over its end;
// Bar.qml cuts those spots out of its input region (cornerCut*) so the wheel reaches the
// window under them, the same arrangement as the Quick Panel's hot edge at the bottom.
Variants {
    id: root

    model: Quickshell.screens

    Scope {
        id: perScreen

        required property var modelData

        component Corner: PanelWindow {
            id: corner

            // "left" | "right"
            required property string side

            screen: perScreen.modelData
            visible: CornerScrollService.enabled
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "sekaipop-corner-scroll"
            anchors {
                top: true
                left: corner.side === "left"
                right: corner.side === "right"
            }
            implicitWidth: CornerScrollService.zoneWidth
            implicitHeight: CornerScrollService.zoneHeight

            // A mouse wheel sends 120 per notch; a touchpad sends many small deltas, which
            // add up so two fingers feel the same: a step for every 120.
            property real acc: 0

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (wheel.angleDelta.y === 0) {
                        wheel.accepted = false
                        return
                    }
                    corner.acc += wheel.angleDelta.y
                    while (corner.acc >= 120) {
                        corner.acc -= 120
                        CornerScrollService.step(corner.side, 1)
                    }
                    while (corner.acc <= -120) {
                        corner.acc += 120
                        CornerScrollService.step(corner.side, -1)
                    }
                }
            }
        }

        Corner {
            side: "left"
        }
        Corner {
            side: "right"
        }
    }
}
