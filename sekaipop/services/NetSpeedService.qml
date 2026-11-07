pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/NetSpeedMath.js" as NSM
import qs.modules.common

// How fast data is moving through the network right now: what the bar's network speed pill
// (NetSpeedIndicator.qml) shows. One reading for the whole shell (every monitor's bar reads this one).
//
//   import qs.services
//   ...
//   NetSpeedService.downText       // "1200" (KB/s)
//
// It reads /proc/net/dev every two seconds and takes the difference between two reads, so a
// speed is the average of the last two seconds. Loopback, containers, virtual machines and
// tunnels are left out (see NetSpeedMath.js), so a VPN's traffic is not counted twice.
//
// The card behind the pill (NetSpeedPopup.qml) also gets the last two minutes as a chart, the peaks,
// and how much has moved since the shell started.
//
// Reading runs only while the pill is switched on (Settings -> Bar -> Modules, "bar.netSpeed"):
// with it off nothing is read.
Singleton {
    id: root

    readonly property bool enabled: SettingsService.flag("bar.netSpeed")

    // Bytes per second, last two seconds.
    property real down: 0
    property real up: 0

    // The pill's texts: kilobytes per second (NetSpeedMath.kbText). The card keeps its own units.
    readonly property string downText: NSM.kbText(root.down)
    readonly property string upText: NSM.kbText(root.up)
    readonly property string tipText: "Download " + NSM.kbLong(root.down) + " · Upload " + NSM.kbLong(root.up)

    // ===== for the card (NetSpeedPopup.qml) =====
    // The last two minutes, one reading every two seconds (bytes per second), oldest first.
    property var downHistory: []
    property var upHistory: []
    // Bars 0..1 for the chart: padded to 60, the newest on the right.
    readonly property var downFracs: NSM.fracs(root.downHistory, 100000)
    readonly property var upFracs: NSM.fracs(root.upHistory, 20000)
    readonly property real peakDown: NSM.peak(root.downHistory)
    readonly property real peakUp: NSM.peak(root.upHistory)
    // Bytes moved since the shell started (while the pill was on).
    property real totalDown: 0
    property real totalUp: 0
    // The interfaces being counted ("wlan0", "eth0").
    property var ifaces: []

    // The reading before this one: { rx, tx, at (ms) }.
    property var previous: null

    onEnabledChanged: {
        // Starting again: the old reading is stale, so the first read only primes it.
        root.previous = null
        if (!root.enabled) {
            root.down = 0
            root.up = 0
            root.downHistory = []
            root.upHistory = []
        }
    }

    FileView {
        id: dev
        path: "/proc/net/dev"
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: {
            dev.reload()
            const now = Date.now()
            const cur = NSM.parseNetDev(dev.text())
            if (root.previous) {
                const r = NSM.rate(root.previous, cur, (now - root.previous.at) / 1000)
                root.down = r.down
                root.up = r.up
                root.downHistory = NSM.pushHistory(root.downHistory, r.down)
                root.upHistory = NSM.pushHistory(root.upHistory, r.up)
                if (cur.rx > root.previous.rx)
                    root.totalDown += cur.rx - root.previous.rx
                if (cur.tx > root.previous.tx)
                    root.totalUp += cur.tx - root.previous.tx
            }
            root.ifaces = cur.ifaces
            root.previous = { rx: cur.rx, tx: cur.tx, at: now }
        }
    }
}
