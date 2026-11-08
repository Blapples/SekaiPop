pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NovelMath.js" as NM
import qs.modules.sekai.readers

// How the novel reader reads a chapter, kept between sessions in
// ~/.local/share/sekaipop/readers/novel/reader.json:
//
//   mode         scroll (one long page) | paged (a screen at a time)
//   background   theme (the shell's own colour) | black | sepia | white
//   fontSize     the chapter's type size, 13 to 26
//   lineHeight   the space between lines, 1.4 to 2.2
//   fullWindow   the panel takes the whole screen (off = the side card on the right edge)
//
// NovelMath.js has the lists and the clean-up of a file that was edited by hand.
Singleton {
    id: root

    property string mode:        NM.DEFAULT_PREFS.mode
    property string background:  NM.DEFAULT_PREFS.background
    property real fontSize:      NM.DEFAULT_PREFS.fontSize
    property real lineHeight:    NM.DEFAULT_PREFS.lineHeight
    property bool fullWindow:    NM.DEFAULT_PREFS.fullWindow

    readonly property string _path: ReaderEnv.dataDir + "/novel/reader.json"

    readonly property var record: ({
        mode: root.mode, background: root.background, fontSize: root.fontSize,
        lineHeight: root.lineHeight, fullWindow: root.fullWindow
    })

    function _apply(raw) {
        const p = NM.normalizePrefs(raw)
        root.mode = p.mode
        root.background = p.background
        root.fontSize = p.fontSize
        root.lineHeight = p.lineHeight
        root.fullWindow = p.fullWindow
    }

    function _save() {
        writer.setText(JSON.stringify(root.record, null, 2))
    }

    function setMode(v)        { if (NM.isMode(v)) { root.mode = v; _save() } }
    function setBackground(v)  { if (NM.isBackground(v)) { root.background = v; _save() } }
    function setFontSize(v)    { root.fontSize = NM.clampFont(v);   _save() }
    function setLineHeight(v)  { root.lineHeight = NM.clampLine(v); _save() }
    function setFullWindow(v)  { root.fullWindow = v === true;      _save() }

    FileView {
        id: reader
        path: root._path
        onLoaded: {
            try { root._apply(JSON.parse(reader.text())) }
            catch (e) { console.warn("[NovelPrefs] parse error:", e); root._apply(null) }
        }
        onLoadFailed: root._apply(null)
    }

    FileView {
        id: writer
        path: root._path
    }

    Component.onCompleted: reader.reload()
}
