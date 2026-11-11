.pragma library

// The clipboard's pinned entries, as plain JavaScript (no QML, no Quickshell) so
// they can be tried on their own (tests/clip-pins-test). The bytes live on disk
// (scripts/state/clip-pins.sh); this only reads its list and decides what the
// Clipboard card shows.
//
//   parsePinList(text)        clip-pins.sh's "<pin>\t<preview>" lines -> entries
//   merge(pins, history)      pins first, then the history without what is pinned
//
// A pinned entry looks like a history one ({ id, preview, image }) plus
// `pinned: true` and `pin` (its name on disk). Its id is "p<pin>", which can
// never be a cliphist id (those are digits only), so the card's "keep the same
// entry picked" and ExtrasSource's "is this answer for the pick" both keep working
// across the two kinds.

function isImagePreview(preview) {
    return /^\[\[\s*binary data/.test(String(preview))
}

function parsePinList(text) {
    var out = []
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var tab = line.indexOf("\t")
        if (tab <= 0)
            continue
        var pin = line.slice(0, tab)
        if (!/^\d+$/.test(pin))
            continue
        var preview = line.slice(tab + 1)
        out.push({ id: "p" + pin, pin: pin, preview: preview, image: isImagePreview(preview), pinned: true })
    }
    return out
}

// A history entry whose preview is the same as a pin's is that pin copied again
// (copying a pin puts it back on the clipboard, and the watcher stores it): it
// is not listed twice. The preview is cliphist's own line -- up to 500 characters
// of the text, or a picture's size, type and dimensions -- so two different
// entries only match when they agree on all of that.
function merge(pins, history) {
    var seen = {}
    for (var i = 0; i < pins.length; i++)
        seen[pins[i].preview] = true
    var out = pins.slice()
    for (var j = 0; j < history.length; j++) {
        if (!seen[history[j].preview])
            out.push(history[j])
    }
    return out
}
