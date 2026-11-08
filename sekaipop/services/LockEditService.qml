pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/LockCanvasModel.js" as LM
import "../modules/common/functions/LockEditMath.js" as EM

// The lockscreen editor's state: whether it is open, which monitor, the board being edited,
// what is selected, and the undo history. State only, like LockCanvasService.qml: the window
// is modules/sekai/lockEditor/LockEditor.qml.
//
// What the editor is: Edit Desktop's twin for the Custom lockscreen. The lockscreen is drawn
// as a framed card on a dark stage, a shelf slides up from the bottom, and you drag the
// widgets (and the password block, a little) where you want them, size them, change their
// options, add and remove them. It is NEVER built on the real lock surface: the lock only
// draws (docs/LOCKCANVAS.md, rule 3 and 4), editing happens here, in your own session.
//
//   qs -c sekaipop ipc call lockedit open | close | toggle
//   (also: right-click the desktop -> Edit lockscreen, and Settings -> General -> Launcher &
//   lock -> Lockscreen style -> Custom -> Edit lockscreen)
//
// How an edit goes: the editor works on a copy of the board (`board`). Every change goes
// through LockCanvasModel.js (so it is checked like a saved file is), is remembered for undo,
// and is handed to LockCanvasService, which saves it. A drag is one edit: `begin()` when it
// starts, `live(board)` as it moves (shown, not saved), `finish()` when it ends.
Singleton {
    id: root

    // ===== state =====
    property bool active: false
    // The monitor being edited. Stays set while the editor closes, so it can finish its exit.
    property string screenName: ""
    // 0 = closed .. 1 = open (overshoots a little on the way in).
    property real progress: 0

    // The board being edited: { core: { x, y }, items: [ { uid, kind, x, y, scale, options } ] }.
    property var board: LM.defaultBoard()
    // A widget's uid, "core" (the password block), or "" for nothing.
    property string selected: ""
    // This monitor has a board of its own, not the shared one every monitor uses.
    property bool ownBoard: false

    property var history: EM.emptyHistory()
    readonly property bool canUndo: root.history.undo.length > 0
    readonly property bool canRedo: root.history.redo.length > 0
    // The board as it was when the drag that is going on began (as text), or "".
    property string gesture: ""

    readonly property int shelfHeight: 220
    readonly property bool styleIsCustom: SettingsService.get("lock.style") === "custom"
    readonly property int monitorCount: Quickshell.screens.length

    // The room: widgets that can not be added any more are shown dim on the shelf.
    readonly property var catalog: LM.kinds().map(k => LM.describe(k))

    // ===== opening and closing =====
    function open(screen) {
        // Not while locked, and not before the saved layout has been read (a save before
        // that would be overwritten by it).
        if (LockState.locked || !LockCanvasService.loaded)
            return
        const name = (typeof screen === "string" && screen !== "") ? screen : EditMode.focusedScreenName()
        if (name === "" || !EditMode.screenPlugged(name))
            return
        if (root.active && root.screenName === name)
            return
        // Edit Desktop is the other thing that takes the whole screen: one at a time.
        if (EditMode.active)
            EditMode.close()
        EditMode.closeMenu()
        root.gesture = ""
        root.screenName = name
        root.ownBoard = LockCanvasService.hasOwnBoard(name)
        root.board = LM.cleanBoard(LockCanvasService.boardFor(name))
        root.selected = ""
        root.history = EM.emptyHistory()
        root.active = true
    }

    function close() {
        if (!root.active)
            return
        // A drag that was still going on is an edit like any other.
        root.finish()
        root.active = false
        root.selected = ""
    }

    function toggle() {
        if (root.active)
            root.close()
        else
            root.open("")
    }

    // The way in is a pop (the card shrinks a touch past its place and settles back); the way
    // out is a plain ease that takes it back. The same times and curves as Edit Desktop's
    // (EditMode.qml: 560 ms OutBack 1.25 in, 360 ms InOutCubic out), so the two feel alike.
    // `progress` is what the editor's window animates (LockEditStage.qml).
    onActiveChanged: root.progress = root.active ? 1 : 0

    Behavior on progress {
        NumberAnimation {
            duration: root.active ? 560 : 360
            easing.type: root.active ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 1.25
        }
    }

    // ===== reading the board =====
    function item(uid) {
        for (const i of root.board.items) {
            if (i.uid === uid)
                return i
        }
        return null
    }

    function countOf(kind) {
        let n = 0
        for (const i of root.board.items) {
            if (i.kind === kind)
                n++
        }
        return n
    }

    function firstUid(kind) {
        for (const i of root.board.items) {
            if (i.kind === kind)
                return i.uid
        }
        return ""
    }

    // Can another one of this widget be put on? (the catalog's limit, and the board's.)
    function canAdd(kind) {
        return root.addPlan(kind) !== null
    }

    function addPlan(kind) {
        const r = LM.addItem(root.board, kind, 0.5, 0.5)
        return r.uid === "" ? null : r
    }

    // Everything that can be selected, in the order Tab goes through it.
    function selectable() {
        const ids = root.board.items.map(i => i.uid)
        ids.push("core")
        return ids
    }

    // ===== selecting =====
    function select(uid) {
        root.selected = (uid === "core" || root.item(uid) !== null) ? uid : ""
    }

    function selectNext(dir) {
        root.selected = EM.cycle(root.selectable(), root.selected, dir)
    }

    // ===== saving =====
    function save() {
        LockCanvasService.setBoard(root.ownBoard ? root.screenName : "*", root.board)
    }

    // One whole edit (a key, a menu): remembered for undo, shown, saved. Nothing happens if
    // it changes nothing.
    function apply(next) {
        const clean = LM.cleanBoard(next)
        if (EM.same(clean, root.board))
            return
        root.history = EM.record(root.history, root.board)
        root.board = clean
        root.save()
    }

    // A drag: begin when it starts, live as it moves, finish when it ends.
    function begin() {
        if (root.gesture === "")
            root.gesture = JSON.stringify(root.board)
    }

    function live(next) {
        root.board = next
    }

    function finish() {
        if (root.gesture === "")
            return
        const before = JSON.parse(root.gesture)
        root.gesture = ""
        if (EM.same(before, root.board))
            return
        root.history = EM.record(root.history, before)
        root.save()
    }

    // ===== edits =====
    // Returns the new widget's uid, or "" when the catalog or the board is full.
    function add(kind, x, y) {
        const r = LM.addItem(root.board, kind, x, y)
        if (r.uid === "")
            return ""
        root.apply(r.board)
        root.selected = r.uid
        return r.uid
    }

    // A click on the shelf: put one on; if that widget only comes once and is already there,
    // select it instead.
    function addOrSelect(kind) {
        if (!root.canAdd(kind)) {
            const have = root.firstUid(kind)
            if (have !== "")
                root.selected = have
            return
        }
        root.add(kind, 0.5, 0.5)
    }

    function remove(uid) {
        if (uid === "core" || root.item(uid) === null)
            return
        root.apply(LM.removeItem(root.board, uid))
        if (root.selected === uid)
            root.selected = ""
    }

    function setOption(uid, key, value) {
        root.apply(LM.setOption(root.board, uid, key, value))
    }

    function setScale(uid, scale) {
        root.apply(LM.scaleItem(root.board, uid, scale))
    }

    function stepScale(uid, dir, step) {
        const it = root.item(uid)
        if (it)
            root.setScale(uid, EM.stepScale(it.scale, dir, step))
    }

    // Arrow keys: move by a fraction of the screen.
    function nudge(uid, dx, dy) {
        if (uid === "core") {
            root.apply(LM.setCore(root.board, root.board.core.x + dx, root.board.core.y + dy))
            return
        }
        const it = root.item(uid)
        if (it)
            root.apply(LM.moveItem(root.board, uid, it.x + dx, it.y + dy))
    }

    function resetLayout() {
        root.apply(LM.defaultBoard())
        root.selected = ""
    }

    function undo() {
        const r = EM.undo(root.history, root.board)
        if (r === null)
            return
        root.finish()
        root.history = r.h
        root.board = LM.cleanBoard(r.board)
        root.select(root.selected)
        root.save()
    }

    function redo() {
        const r = EM.redo(root.history, root.board)
        if (r === null)
            return
        root.finish()
        root.history = r.h
        root.board = LM.cleanBoard(r.board)
        root.select(root.selected)
        root.save()
    }

    // ===== this monitor only =====
    // On: this monitor gets a copy of the board on screen and keeps its own from now on.
    // Off: it wears the shared board again (what you see here changes to it).
    function setOwnBoard(on) {
        if (!root.active || on === root.ownBoard)
            return
        if (on) {
            root.ownBoard = true
            root.save()
            return
        }
        root.ownBoard = false
        LockCanvasService.dropBoard(root.screenName)
        root.history = EM.record(root.history, root.board)
        root.board = LM.cleanBoard(LockCanvasService.boardFor(root.screenName))
        root.select(root.selected)
    }

    // The editor is pointless unless Custom is the style: one key on the shelf says so.
    function useCustom() {
        SettingsService.set("lock.style", "custom")
    }

    // The session locked (a keybind, hypridle): the editor must not stay over the lock.
    Connections {
        target: LockState

        function onLockedChanged() {
            if (LockState.locked)
                root.close()
        }
    }

    // A desktop preset put its own lockscreen layout on while the editor was open (the
    // `presets apply` call): the board here is the one it replaced, and the next edit would save
    // it back over the preset's. Close without saving (a drag that was going on is let go).
    Connections {
        target: LockCanvasService

        function onReplaced() {
            if (!root.active)
                return
            root.gesture = ""
            root.close()
        }
    }

    // ===== choosing a picture (the Image widget) =====
    // The file chooser is a normal window, which the editor (an Overlay layer on top of
    // everything) would cover, so the editor steps aside while it is open (`picking`) and
    // comes back when it closes. What was being edited is kept here, so nothing is lost.
    property bool picking: false
    property string pickUid: ""
    readonly property string pickScript: Directories.script("images/pick-lock-picture.sh")

    function pickPicture(uid) {
        if (root.picking || root.item(uid) === null)
            return
        root.pickUid = uid
        root.picking = true
        pickProc.running = true
    }

    Process {
        id: pickProc

        command: PanelImages.chooser === ""
            ? ["sh", root.pickScript, "pick"]
            : ["env", "SEKAIPOP_CHOOSER=" + PanelImages.chooser, "sh", root.pickScript, "pick"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                // The model checks the path again (absolute, a picture, no tricks).
                if (path !== "" && root.active && root.item(root.pickUid) !== null)
                    root.setOption(root.pickUid, "path", path)
            }
        }
        onExited: root.picking = false
    }

    // ===== ipc =====
    IpcHandler {
        target: "lockedit"

        function open(): void {
            root.open("");
        }

        function close(): void {
            root.close();
        }

        function toggle(): void {
            root.toggle();
        }
    }
}
