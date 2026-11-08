pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/LockCanvasModel.js" as LM

// The Custom lockscreen's layout: which widgets are on it, where, and their options --
// state only, like ClockService.qml: no window, no pixels. LockCanvas.qml draws it.
//
//   LockCanvasService.boardFor("DP-1")     that monitor's board (the shared one if it has none)
//   LockCanvasService.setBoard("DP-1", b)  replace it (the editor does this; "*" is the shared one)
//   LockCanvasService.hasOwnBoard("DP-1")  true if that monitor has a board of its own
//   LockCanvasService.dropBoard("DP-1")    that monitor wears the shared board again
//   LockCanvasService.reset()              back to the first layout
//   LockCanvasService.presetPart()         the layout as a desktop preset holds it
//   LockCanvasService.wearPreset(part)     put a desktop preset's layout on (see below)
//
//   qs -c sekaipop ipc call lockcanvas reset
//
// What the rules are (known widgets only, numbers in range, the password block always
// there) lives in LockCanvasModel.js; every board that comes in, from the saved file or from
// an edit, goes through it. The saved file is data only and is never run as code.
//
// Nothing here waits for the file: until it has been read, and if it can not be, the first
// layout is what the lockscreen shows, so locking never depends on this loading.
Singleton {
    id: root

    // False until the saved layout has been read. Nothing is written before then, or a
    // fresh start would overwrite what is on disk with the defaults.
    property bool loaded: false

    // { v, boards: { "*": board, "DP-1": board, ... } }, always clean (LockCanvasModel.parse).
    property var model: LM.defaultModel()

    function boardFor(screen) {
        return LM.boardFor(root.model, screen)
    }

    // Emitted after the layout was changed by the person (the editor, `reset`), not when a preset
    // put its own on: DesktopPresetService writes the change into the preset you are in.
    signal edited()

    function setBoard(screen, board) {
        root.model = LM.withBoard(root.model, screen, board)
        root.persist()
        root.edited()
    }

    function hasOwnBoard(screen) {
        return LM.hasBoard(root.model, screen)
    }

    function dropBoard(screen) {
        root.model = LM.dropBoard(root.model, screen)
        root.persist()
        root.edited()
    }

    function reset() {
        root.model = LM.defaultModel()
        root.persist()
        root.edited()
    }

    // ===== desktop presets =====
    // A preset holds every board and the list of widgets the shell had (LockCanvasModel.presetPart),
    // so each preset has a lockscreen of its own. DesktopPresetService calls these two.
    //
    // Same rule as the desktop widgets: a preset wears what it holds, and a widget it
    // could not hold, because it was saved before that widget existed, is not shown:
    //   - a preset with a layout puts it on, minus any widget not in its list;
    //   - a preset saved before layouts were part of one has none: your layout stays where it
    //     is, but only the widgets that existed then (LockCanvasModel.legacyKinds) are kept;
    //     the newer ones come off the boards.
    // The password block is never touched by either.

    // Emitted when a preset has replaced the boards: the lockscreen editor holds a copy of
    // one, and must not save that copy back over what the preset just put on.
    signal replaced()

    function presetPart() {
        return LM.presetPart(root.model)
    }

    function wearPreset(part) {
        // Not before the saved layout has been read: restore() would replace whatever is put
        // on now with the file's.
        if (!root.loaded)
            return
        const worn = LM.wornModel(part)
        root.model = worn !== null ? worn : LM.keepKinds(root.model, LM.legacyKinds())
        root.persist()
        root.replaced()
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/lockcanvas-state.sh")

    function restore(text) {
        // An empty or unreadable file is the first layout (LockCanvasModel.parse).
        root.model = LM.parse(text)
        root.loaded = true
    }

    // Runs once, at startup.
    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: root.restore(text)
        }
    }

    function persist() {
        if (root.loaded)
            saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: saver.save(LM.stringify(root.model))
    }

    // Fire-and-forget save. Queues at most one pending snapshot behind an in-flight save
    // rather than dropping it, so the *last* state is what ends up on disk (same reasoning
    // as ClockService's `saver`).
    Process {
        id: saver

        property var pending: null

        function save(json) {
            if (saver.running) {
                saver.pending = json
                return
            }
            saver.pending = null
            saver.exec(["sh", root.script, "save", json])
        }

        onExited: {
            if (saver.pending !== null) {
                const json = saver.pending
                saver.pending = null
                saver.exec(["sh", root.script, "save", json])
            }
        }
    }

    IpcHandler {
        target: "lockcanvas"

        function reset(): void {
            root.reset()
        }
    }
}
