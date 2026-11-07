pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/SensorsMath.js" as SM
import qs.modules.common

// The CPU and GPU temperatures and the disks' free space: the extra rows of the CPU & RAM card
// (ResourcePopup.qml) and the temperature in that pill's hover tag. One reading for the whole
// shell, from scripts/system/sensors.sh (sysfs and df; see the script for what it can read).
//
//   import qs.services
//   ...
//   SensorsService.cpuTemp         // 62, or null when this machine has no sensor we can read
//   SensorsService.disks           // [{ mount: "/", used: bytes, total: bytes }, ...]
//
// Read every ten seconds while the CPU & RAM pill is switched on (Settings -> Bar -> Modules);
// with it off nothing is read.
Singleton {
    id: root

    readonly property bool enabled: SettingsService.flag("bar.resources")

    property var cpuTemp: null
    property var gpuTemp: null
    property var disks: []

    // False until the first reading is in (the card shows nothing for the rows till then).
    property bool loaded: false

    readonly property string script: Directories.script("system/sensors.sh")

    // "62°C", or "" when unknown: for the hover tag.
    readonly property string cpuTempText: root.cpuTemp === null ? "" : SM.tempText(root.cpuTemp)

    function apply(text) {
        const r = SM.parse(text)
        root.cpuTemp = r.cpuTemp
        root.gpuTemp = r.gpuTemp
        root.disks = r.disks
        root.loaded = true
    }

    Process {
        id: reader
        command: ["sh", root.script]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: if (!reader.running) reader.running = true
    }
}
