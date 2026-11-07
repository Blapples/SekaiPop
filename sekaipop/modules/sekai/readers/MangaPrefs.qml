pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ReaderMath.js" as RM
import qs.modules.sekai.readers

// How the manga reader reads a chapter, kept between sessions in
// ~/.local/share/sekaipop/readers/manga/reader.json (next to the library):
//
//   auto         a manhwa / long-strip series opens in `webtoonMode` by itself
//   mode         the reading mode for everything else (and for everything when `auto` is off)
//   webtoonMode  the reading mode of a long-strip series
//   background   black | gray | white | theme (the shell's own colour)
//   spreadCover  Tablet mode: the first page stands alone, like a cover
//   fullWindow   the panel takes the whole screen (off = the side card on the left edge)
//
// ReaderMath.js has the list of modes and the clean-up of a file that was edited by hand.
Singleton {
    id: root

    property bool auto:        RM.DEFAULT_PREFS.auto
    property string mode:        RM.DEFAULT_PREFS.mode
    property string webtoonMode: RM.DEFAULT_PREFS.webtoonMode
    property string background:  RM.DEFAULT_PREFS.background
    property bool spreadCover: RM.DEFAULT_PREFS.spreadCover
    property bool fullWindow:  RM.DEFAULT_PREFS.fullWindow

    readonly property string _path: ReaderEnv.dataDir + "/manga/reader.json"

    // The settings as ReaderMath wants them (resolveMode, ...).
    readonly property var record: ({
        auto: root.auto, mode: root.mode, webtoonMode: root.webtoonMode,
        background: root.background, spreadCover: root.spreadCover,
        fullWindow: root.fullWindow
    })

    function _apply(raw) {
        const p = RM.normalizePrefs(raw)
        root.auto = p.auto
        root.mode = p.mode
        root.webtoonMode = p.webtoonMode
        root.background = p.background
        root.spreadCover = p.spreadCover
        root.fullWindow = p.fullWindow
    }

    function _save() {
        writer.setText(JSON.stringify(root.record, null, 2))
    }

    function setAuto(v)        { root.auto = v === true;                _save() }
    function setBackground(v)  { if (RM.isBackground(v)) { root.background = v; _save() } }
    function setSpreadCover(v) { root.spreadCover = v === true;         _save() }
    function setFullWindow(v)  { root.fullWindow = v === true;          _save() }

    // The mode picked while reading: it is the long-strip series' mode when that is what is
    // being read (and `auto` is on), else the general one.
    function setModeFor(modeId, webtoon) {
        if (!RM.isMode(modeId)) return
        if (root.auto && webtoon === true) root.webtoonMode = modeId
        else root.mode = modeId
        _save()
    }

    FileView {
        id: reader
        path: root._path
        onLoaded: {
            try { root._apply(JSON.parse(reader.text())) }
            catch (e) { console.warn("[MangaPrefs] parse error:", e); root._apply(null) }
        }
        onLoadFailed: root._apply(null)
    }

    FileView {
        id: writer
        path: root._path
    }

    Component.onCompleted: reader.reload()
}
