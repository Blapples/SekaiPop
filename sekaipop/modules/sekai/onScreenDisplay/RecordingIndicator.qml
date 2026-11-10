import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A red "● REC 01:23" pill in the top-right corner of every screen, just inside the
// bar, for as long as the screen is being recorded: by the shell's own region
// recorder (RegionService) or by any recorder started some other way (wf-recorder,
// wl-screenrec, gpu-screen-recorder: looked for every 2 s, only `pgrep`). The dot
// pulses. Clicking the pill stops the recording the way the recorder wants it
// (SIGINT, which makes wf-recorder finish the file properly).
Variants {
    id: root

    readonly property int gap: 14
    // Process names as pgrep -x sees them: the kernel keeps only the first 15 characters,
    // so gpu-screen-recorder is "gpu-screen-reco".
    readonly property var recorders: ["wf-recorder", "wl-screenrec", "gpu-screen-reco"]

    property bool external: false
    readonly property bool recording: RegionService.recording || root.external
    // When the current recording started (ms), for the timer on the pill.
    property real since: 0
    property real now: 0

    onRecordingChanged: {
        root.since = Date.now()
        root.now = root.since
    }

    property Process poll: Process {
        command: ["pgrep", "-x", "-c", root.recorders.join("|")]
        stdout: StdioCollector {
            onStreamFinished: root.external = parseInt(text) > 0
        }
    }

    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.poll.running = true
    }

    property Timer clock: Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.now = Date.now()
    }

    function elapsed() {
        const s = Math.max(0, Math.floor((root.now - root.since) / 1000))
        const two = n => (n < 10 ? "0" : "") + n
        const h = Math.floor(s / 3600)
        return (h > 0 ? h + ":" : "") + two(Math.floor(s / 60) % 60) + ":" + two(s % 60)
    }

    function stop() {
        if (RegionService.recording)
            RegionService.stopRecording()
        if (root.external)
            Quickshell.execDetached(["pkill", "-INT", "-x", root.recorders.join("|")])
    }

    model: Quickshell.screens

    PanelWindow {
        id: win

        required property var modelData
        screen: modelData

        readonly property var mt: Theme.of(win.screen)
        property real revealed: root.recording ? 1 : 0
        Behavior on revealed {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        visible: revealed > 0.001
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "sekaipop-recording"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        readonly property real uiScale: ShellScale.forScreen(win.screen)
        readonly property real barOffset: Math.round((BarPositionService.thickness + root.gap) * win.uiScale)
        readonly property real edge: Math.round(root.gap * win.uiScale)

        anchors {
            top: true
            right: true
        }
        margins {
            top: BarPositionService.position === "top" ? win.barOffset : win.edge
            right: BarPositionService.position === "right" ? win.barOffset : win.edge
        }

        implicitWidth: Math.ceil(pill.width * win.uiScale)
        implicitHeight: Math.ceil(pill.height * win.uiScale)

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Rectangle {
                id: pill
                width: row.implicitWidth + 28
                height: 36
                radius: height / 2
                color: hit.containsMouse ? "#B71C1C" : "#D32F2F"
                border.width: 2
                border.color: win.mt.colBorder
                opacity: win.revealed
                scale: 0.88 + 0.12 * win.revealed

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        id: dot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
                        color: "white"
                        visible: !hit.containsMouse

                        SequentialAnimation on opacity {
                            running: root.recording
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hit.containsMouse
                        name: "stop"
                        size: 18
                        color: "white"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: hit.containsMouse ? "Stop" : "REC " + root.elapsed()
                        color: "white"
                        font.family: win.mt.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stop()
                }
            }
        }
    }
}
