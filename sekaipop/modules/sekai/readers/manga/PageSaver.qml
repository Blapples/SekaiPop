import QtQuick
import Quickshell
import Quickshell.Io

// Saves a page of the chapter as a picture: the original file (the image proxy hands back
// what the source sent, so nothing is re-encoded), into
//
//   <Pictures>/SekaiPop/<manga title>/<manga title> - <chapter> - p012.<jpg|png|webp>
//
// One at a time, in the order asked. `saved(path, label)` / `failed(label)` say how each ended.
//
//   saver.save(url, "Solo Leveling", "Solo Leveling - Chapter 12 - p003", "p. 3")
Item {
    id: root

    signal saved(string path, string label)
    signal failed(string label)

    readonly property bool busy: saver.running || root._queue.length > 0

    property var _queue: []
    property string _label: ""
    property string _path: ""
    property bool _streamDone: false
    property bool _exitDone: false
    property int _code: 0

    // $1 url, $2 folder (under Pictures/SekaiPop), $3 file name without extension
    readonly property string script:
        "u=\"$1\"; d=\"$2\"; b=\"$3\"\n"
        + "P=$(xdg-user-dir PICTURES 2>/dev/null)\n"
        + "case \"$P\" in \"\"|\"$HOME\") P=\"$HOME/Pictures\";; esac\n"
        + "out=\"$P/SekaiPop/$d\"; mkdir -p \"$out\" || exit 1\n"
        + "t=$(mktemp) || exit 1\n"
        + "ct=$(curl -fsSL --max-time 90 -o \"$t\" -w '%{content_type}' \"$u\") || { rm -f \"$t\"; exit 2; }\n"
        + "case \"$ct\" in *png*) e=png;; *webp*) e=webp;; *gif*) e=gif;; *avif*) e=avif;; *jpeg*|*jpg*) e=jpg;; *)\n"
        + "  m=$(file -b --mime-type \"$t\" 2>/dev/null)\n"
        + "  case \"$m\" in image/png) e=png;; image/webp) e=webp;; image/gif) e=gif;; image/avif) e=avif;; *) e=jpg;; esac;;\n"
        + "esac\n"
        + "f=\"$out/$b.$e\"\n"
        + "mv -f \"$t\" \"$f\" && chmod 644 \"$f\" && printf '%s\\n' \"$f\"\n"

    function save(url, folder, baseName, label) {
        if (!url || url.length === 0) {
            root.failed(label)
            return
        }
        root._queue = root._queue.concat([{ url: url, folder: folder, base: baseName, label: label }])
        root._next()
    }

    function _next() {
        if (saver.running || root._queue.length === 0)
            return
        const job = root._queue[0]
        root._queue = root._queue.slice(1)
        root._label = job.label
        root._path = ""
        root._streamDone = false
        root._exitDone = false
        saver.command = ["sh", "-c", root.script, "sekaipop-save", job.url, job.folder, job.base]
        saver.running = true
    }

    function _finish() {
        if (!root._streamDone || !root._exitDone)
            return
        const path = root._path.trim()
        if (root._code === 0 && path.length > 0)
            root.saved(path, root._label)
        else
            root.failed(root._label)
        root._next()
    }

    Process {
        id: saver
        stdout: StdioCollector {
            onStreamFinished: {
                root._path = text
                root._streamDone = true
                root._finish()
            }
        }
        onExited: (code) => {
            root._code = code
            root._exitDone = true
            root._finish()
        }
    }
}
