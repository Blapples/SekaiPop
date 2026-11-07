pragma Singleton
import Quickshell

// Where the manga and novel backends live and which Python runs them.
//
// The servers (scripts/readers/) need `curl_cffi` or `requests`. scripts/readers/setup-venv.sh
// makes a private venv with both (~/.local/share/sekaipop/readers/venv); when that venv is there
// the servers run under it, otherwise under the system python3.
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string dataDir: home + "/.local/share/sekaipop/readers"
    readonly property string venvPython: dataDir + "/venv/bin/python3"
    readonly property string scripts: Quickshell.shellPath("scripts/readers")

    // A reader panel is changing its width (the size key, a chapter going full-screen). The things
    // that are costly to redraw on every frame of that (a halftone Canvas, the wrapped titles of
    // every cover in a grid) hold still while it is true and catch up when it turns false.
    property bool panelResizing: false
    // The body width (the panel's width less its two margins) that the current move ends at.
    // While `panelResizing` the covers' grids lay themselves out at THIS width from the first
    // frame and hold it, and the card's edge only uncovers or covers them (a reveal), instead of
    // every cover of the grid being resized on every frame of the move.
    property real panelBodyTarget: 0

    // The command line that starts one of the servers: the venv's python if it exists,
    // else the system python3 (a missing file is tested by the shell, so no async check).
    function command(script) {
        return ["sh", "-c", "P=\"$1\"; [ -x \"$P\" ] || P=python3; shift; exec \"$P\" \"$@\"", "reader", venvPython, script]
    }
}
