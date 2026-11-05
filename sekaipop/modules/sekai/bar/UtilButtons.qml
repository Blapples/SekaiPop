import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The bar's utility buttons, joined into one long navy pill (same
// radiusBadge corners and hard shadow as the other bar widgets) with a
// flat glyph cell per button. Left to right:
//
//   Screen snip        grim + slurp, saved to ~/Pictures/Screenshots
//                      and copied to the clipboard (wl-copy)
//   Color picker       hyprpicker -a (hex goes straight to the clipboard)
//   Keyboard           on-screen keyboard on/off (the shell's own, wtype types for it)
//   Mic                mute / unmute the default mic (lit = muted)
//   Dark / light       flips the shell's dark mode and the system colour scheme (glyph shows the
//                      current mode)
//   Performance        cycles power-saver -> balanced -> performance
//                      (power-profiles-daemon; lit = performance)
//   Record screen      pick a region, record it with wf-recorder to
//                      ~/Videos/Recordings; click again to stop (lit
//                      while recording)
//   Wallpapers         opens the wallpaper picker
//
// If a tool isn't installed the button just does nothing — same
// "missing tool doesn't stop the shell" rule QuickSource.qml follows.
// Install whichever you want: `grim`, `slurp`, `wl-clipboard`,
// `hyprpicker`, `wtype`, `wf-recorder`, `power-profiles-daemon`.
//
// Dark / light uses illogical-impulse's switchwall.sh when it's there
// (so matugen + GTK/Qt colours follow), else just sets the GNOME
// color-scheme setting.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // True on a standing bar (left / right edge): the buttons stack in a
    // column, top to bottom in the same order.
    property bool vertical: false

    // Which edge the bar is on, so the hover tags open towards the screen.
    property string barPosition: "top"

    // True on a standing bar that is too short for the whole column (Status_Bar
    // `utilFlyout`): the pill is then one tools key, and the keys are in the flyout
    // card it opens (UtilPopup.qml; Bar.qml owns it). `popupOpen` lights the key while
    // the card is up; `toggleItem` is what the card grows out of.
    property bool compact: false
    property bool popupOpen: false
    readonly property Item toggleItem: bar
    signal toggleRequested()

    implicitWidth: bar.width
    implicitHeight: bar.height

    // Asks the bar (Bar.qml) to open the wallpaper picker.
    signal wallpapersRequested()

    // ===== Mic =====
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSource]
    }
    readonly property var micAudio: Pipewire.defaultAudioSource?.audio ?? null
    readonly property bool micMuted: micAudio ? micAudio.muted : false

    function toggleMic() {
        if (micAudio)
            micAudio.muted = !micAudio.muted
    }

    // ===== Dark / light =====
    property bool darkMode: true

    Process {
        running: true
        command: [
            "setpriv", "--pdeathsig", "TERM", "bash", "-c",
            "gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null; "
            + "exec gsettings monitor org.gnome.desktop.interface color-scheme 2>/dev/null"
        ]
        stdout: SplitParser {
            onRead: line => {
                root.schemeIsDark = line.indexOf("prefer-dark") !== -1
                root.followScheme()
            }
        }
    }

    // What GNOME's color-scheme says right now. While system-theme.sh is
    // applying colours it flips the scheme to the opposite value and back for
    // a moment (to make libadwaita apps repaint), so that is not followed
    // until the run has settled; the last value seen is then the real one.
    property bool schemeIsDark: true
    property bool schemeSeen: false

    function followScheme() {
        // A first run starts dark and has just asked the system for a dark scheme.
        // Until it arrives, a light (or unset) scheme is not followed.
        if (ThemeService.firstDarkPending) {
            if (!root.schemeIsDark)
                return
            ThemeService.firstDarkDone()
        }
        if (ThemeService.systemBusy) {
            root.schemeSeen = true
            return
        }
        root.schemeSeen = false
        root.darkMode = root.schemeIsDark
        // The shell always matches the system scheme, so the two
        // can never end up on opposite sides.
        ThemeService.setDark(root.darkMode)
    }

    Connections {
        target: ThemeService
        function onSystemBusyChanged() {
            if (!ThemeService.systemBusy && root.schemeSeen)
                root.followScheme()
        }
    }

    function toggleDarkMode() {
        ThemeService.cycleModeAndSystem()
    }

    // ===== Performance profile =====
    readonly property bool performanceOn: PowerProfiles.profile === PowerProfile.Performance
    readonly property string profileIcon: PowerProfiles.profile === PowerProfile.PowerSaver
        ? "energy_savings_leaf"
        : (PowerProfiles.profile === PowerProfile.Performance ? "speed" : "balance")

    function cycleProfile() {
        const p = PowerProfiles.profile
        if (p === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced
        else if (p === PowerProfile.Balanced)
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance : PowerProfile.PowerSaver
        else
            PowerProfiles.profile = PowerProfile.PowerSaver
    }

    // ===== On-screen keyboard =====
    // One shared state with the Quick Panel's Keyboard tile: KeyboardService.qml.

    // ===== Screen recording =====
    property string recordFile: ""
    // Recording now (by wf-recorder here, or by our own region picker).
    readonly property bool recording: recorder.running || RegionService.recording

    Process {
        id: recorder
        onRunningChanged: {
            if (!running && root.recordFile !== "") {
                Quickshell.execDetached(["bash", "-c",
                    "[ -s \"$1\" ] && notify-send -a sekaipop -i material:videocam \"Recording saved\" \"$1\"",
                    "bash", root.recordFile])
                root.recordFile = ""
            }
        }
    }

    function toggleRecording() {
        // Our own picker (Settings -> General -> Own region picker).
        if (SettingsService.flag("region.own")) {
            if (RegionService.recording)
                RegionService.stopRecording()
            else
                RegionService.show("record", "")
            return
        }
        if (recorder.running) {
            recorder.signal(2)
            return
        }
        const dir = Quickshell.env("HOME") + "/Videos/Recordings"
        root.recordFile = dir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4"
        // The encoder is picked by region-action.sh (NVENC, VAAPI or software, whichever works).
        recorder.command = ["bash", "-c",
            "mkdir -p \"$(dirname \"$1\")\"; g=$(slurp) || exit 0; exec sh \"$2\" record \"$g\" none \"$1\"",
            "bash", root.recordFile, Directories.script("system/region-action.sh")]
        recorder.running = true
    }

    function screenshotRegion() {
        if (SettingsService.flag("region.own")) {
            RegionService.show("copy", "")
            return
        }
        const script = [
            "dir=\"$HOME/Pictures/Screenshots\"",
            "mkdir -p \"$dir\"",
            "f=\"$dir/$(date +%Y-%m-%d_%H-%M-%S).png\"",
            "grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send -a sekaipop -i material:photo_camera \"Screenshot saved\" \"$f\""
        ].join("; ")
        Quickshell.execDetached(["bash", "-c", script])
    }

    function pickColor() {
        Quickshell.execDetached(["hyprpicker", "-a"])
    }

    // ===== The long bar =====
    // What the pill holds: the whole list of keys, or (compact) one tools key.
    readonly property Item content: root.compact ? toolKey : row

    Pill {
        id: bar
        width: root.vertical ? bar.barVWidth : root.content.implicitWidth + 2 * ringWidth + 2 * 4
        height: root.vertical
            ? root.content.implicitHeight + (bar.capsule ? 4 : 2 * ringWidth) + 2 * 4 + mt.shadowOffset
            : mt.pillHeight + mt.shadowOffset
        cornerRadius: mt.radiusBadge
        ringWidth: 6
        fillColor: mt.chipFill

        // A GridLayout so it can be a row or a column (100 columns is
        // "all in one row"). The keys themselves are UtilKeys.qml.
        UtilKeys {
            id: row
            anchors.centerIn: parent
            visible: !root.compact
            src: root
            tips: true
            barPosition: root.barPosition
            columns: root.vertical ? 1 : 100
        }

        // Compact: just the tools key; it lights while the flyout is up.
        UtilKey {
            id: toolKey
            anchors.centerIn: parent
            visible: root.compact
            label: "Utility keys"
            tip: true
            barPosition: root.barPosition
            icon: "construction"
            active: root.popupOpen
            onClicked: root.toggleRequested()
        }
    }
}
