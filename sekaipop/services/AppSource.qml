import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import "../modules/common/functions/AppUsage.js" as AU

// The system side of the App Launcher — every installed .desktop
// application, via Quickshell's own DesktopEntries index (no shelling
// out, unlike QuickSource.qml's nmcli/bluetoothctl/wpctl calls: this
// one's a real Quickshell API). The Apps screen (LauncherFace.qml) stays
// pure UI; it hands this file a query string and reads back an ordered
// list of matches to draw as tiles.
//
// Built to be cheap to ask, because the Apps screen asks on every key:
//
//   - `entries`: ONE plain object per app, built once (and again only when
//     apps are installed / removed), name-sorted, carrying the lower-cased
//     search fields. Typing never touches the DesktopEntry objects again
//     (each read of one is a trip into C++), it just compares strings.
//   - the objects are STABLE: the same app is the same object every time, so
//     a ScriptModel can tell which tiles stay and which come and go (see
//     LauncherFace.qml) instead of tearing down and rebuilding the whole grid
//     per letter. That holds across Quickshell's rescans too: an app whose
//     DesktopEntry and fields did not change keeps its entry object.
//   - `iconFor()` remembers every icon path it has looked up.
//
// Launches are counted (AppUsage.js) for the "Most used" order, Settings > General >
// Launcher & lock > Apps order (launcher.order: "az" | "used"). Only launches from the
// Apps screen count: the dock's own clicks run the entry directly (Dock.qml).
Scope {
    id: root

    property string query: ""

    // Plain-JS scratch that must NOT be a reactive property: the ranking and
    // icon caches are written while a binding is being evaluated, and writing
    // a property from inside a binding that read it is a binding loop. Changing
    // the *fields* of this one object notifies nobody.
    readonly property var _cache: ({
        rankKey: "", rankVal: [],
        iconSrc: null, icons: ({}),
        usage: ({}), usageDirty: false
    })

    // Every non-hidden, non-NoDisplay application on the system
    // (DesktopEntries.applications already filters those out), name-sorted
    // so there's a stable base order to rank from.
    //
    // NOT a binding on `DesktopEntries.applications.values` (issue #128). Quickshell
    // rescans every application folder whenever a file appears or goes in that folder
    // *or any folder above it* (its monitor watches the parents up to /), so a shell
    // writing its history in ~ or a player rewriting ~/.local/share/recently-used.xbel
    // starts a rescan. The rescan then updates the model one row at a time, and
    // `valuesChanged` fires per row: every app found in two data folders (a
    // ~/.local/share override, a folder listed twice in XDG_DATA_DIRS) gets a new
    // DesktopEntry each scan and costs two signals. With /usr/share listed twice that
    // was 312 signals for one rescan of 224 apps, and a binding on `.values` rebuilt and
    // re-sorted the whole list on each of them: the shell froze at 100% CPU.
    //
    // So the list is rebuilt from code, once per finished scan (`applicationsChanged`
    // below) and whenever the Apps screen opens (`sync()`), and only when the apps
    // really differ from the ones it was built from.
    property var _entries: []
    readonly property var entries: root._entries

    // Does `list` hold exactly the DesktopEntry objects the list was built from? One
    // pass and no reads into C++: an app Quickshell replaced is a different object.
    function sameApps(list) {
        const built = root._cache.byApp
        if (!built || built.size !== list.length)
            return false
        for (let i = 0; i < list.length; i++)
            if (!built.has(list[i]))
                return false
        return true
    }

    // Reads every app's fields and rebuilds `entries` if anything changed. Run once per
    // scan: that is also when an edited .desktop file's new name or icon arrives (the
    // same DesktopEntry, updated in place).
    function refresh() {
        const next = root.buildEntries(DesktopEntries.applications.values)
        if (next !== root._entries)
            root._entries = next
    }

    // The Apps screen is opening: pick up apps installed since the list was built (the
    // check that costs nothing when none were), and move the "Most used" order on.
    function sync() {
        if (!root.sameApps(DesktopEntries.applications.values))
            root.refresh()
        if (root._cache.usageDirty) {
            root._cache.usageDirty = false
            root._usageRev++
        }
    }

    Component.onCompleted: root.refresh()

    // Emitted once per finished scan, after the model has every row in place. Run
    // straight away, not deferred: the apps the old list points at are deleted
    // (deleteLater) as soon as the event loop turns.
    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.refresh()
        }
    }

    // ===== most used =====
    readonly property bool byUse: SettingsService.get("launcher.order") === "used"

    // The counts are read from `_cache.usage` when this changes, not on every launch:
    // a launch only marks them dirty, and `sync()` (the Apps screen opening) moves the
    // order on. Re-sorting at launch would shuffle the tiles while the phone slides away.
    property int _usageRev: 0

    // What the grid shows with nothing typed: `entries` A to Z, or most used first.
    // The same objects either way. A score's decay is the same for every app, so the
    // order doesn't drift with time on its own and needs no timer.
    readonly property var ordered: {
        root._usageRev
        return root.byUse ? AU.order(root.entries, root._cache.usage, Date.now()) : root.entries
    }

    readonly property string usageScript: Directories.script("state/app-usage-state.sh")

    Process {
        running: true
        command: ["sh", root.usageScript, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._cache.usage = AU.parse(text)
                root._usageRev++
            }
        }
    }

    function recordLaunch(app) {
        const id = app.id || ""
        if (id === "")
            return
        root._cache.usage = AU.record(root._cache.usage, id, Date.now())
        root._cache.usageDirty = true
        Quickshell.execDetached(["sh", root.usageScript, "save", JSON.stringify(root._cache.usage)])
    }

    // The same apps as plain DesktopEntry objects (what this file used to
    // hand out); kept for anything that still wants them.
    readonly property var allApps: root.entries.map(e => e.app)

    // Matches for the current query, best match first. Empty query ->
    // empty list on purpose: the results card only shows up once
    // you've actually typed something.
    readonly property var results: root.query.length === 0 ? [] : root.rank(root.query)

    // The entries for `list`, name-sorted. Each app's fields are read once. When every
    // app is the same DesktopEntry with the same fields as last time, the previous
    // array itself comes back (nothing downstream re-runs); otherwise an app that did
    // not change keeps its entry object, and only new or changed apps get new ones.
    function buildEntries(list) {
        const c = root._cache
        const built = c.byApp || new Map()
        const old = root._entries || []
        const rows = new Array(list.length)
        let same = list.length === old.length
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            let kw = ""
            const kws = a.keywords || []
            for (const k of kws)
                kw += k + "\n"
            const name = a.name || ""
            const generic = a.genericName || ""
            const icon = a.icon || ""
            const comment = a.comment || ""
            const sig = name + "\u0001" + generic + "\u0001" + icon + "\u0001" + comment + "\u0001" + kw
            const prev = built.get(a)
            if (!prev || prev.sig !== sig)
                same = false
            rows[i] = { a: a, id: a.id, name: name, generic: generic, icon: icon, comment: comment, kw: kw, sig: sig, prev: prev }
        }
        if (same)
            return old
        rows.sort((x, y) => x.name.localeCompare(y.name))
        const seen = ({})
        const out = new Array(rows.length)
        const byApp = new Map()
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i]
            // A key the grid can tell apps apart by. Desktop ids are unique; the
            // counter is only there so a odd duplicate can never collide.
            let key = r.id || (r.name + "\u0001" + r.icon)
            if (seen[key] !== undefined)
                key = key + "#" + (++seen[key])
            else
                seen[key] = 0
            let e = r.prev
            if (e && e.sig === r.sig && e.key === key) {
                e.idx = i
            } else {
                e = {
                    key: key,
                    idx: i,
                    app: r.a,
                    sig: r.sig,
                    name: r.name,
                    icon: r.icon,
                    generic: r.generic,
                    nameL: r.name.toLowerCase(),
                    genericL: r.generic.toLowerCase(),
                    keywordsL: r.kw.toLowerCase(),
                    commentL: r.comment.toLowerCase()
                }
            }
            out[i] = e
            byApp.set(r.a, e)
        }
        c.byApp = byApp
        return out
    }

    // Matches (as the entries above), best first. The result for the last query
    // is remembered, so asking twice for the same text costs nothing.
    function rankEntries(q) {
        const needle = (q || "").toLowerCase().trim()
        if (needle === "")
            return []
        const list = root.entries
        const c = root._cache
        // With "Most used" on, ties (two apps whose names both start with what you typed)
        // go to the one you open more.
        const byUse = root.byUse
        const rev = root._usageRev
        if (c.rankSrc === list && c.rankKey === needle && c.rankByUse === byUse && c.rankRev === rev)
            return c.rankVal
        const now = Date.now()
        const scored = []
        for (let i = 0; i < list.length; i++) {
            const s = root.scoreEntry(list[i], needle)
            if (s > 0)
                scored.push({ e: list[i], s: s, u: byUse ? AU.scoreAt(c.usage[list[i].key], now) : 0 })
        }
        // Ties go to the more used app (with "Most used" on), then keep the name order (idx).
        scored.sort((a, b) => b.s - a.s || b.u - a.u || a.e.idx - b.e.idx)
        const out = scored.map(x => x.e)
        c.rankSrc = list
        c.rankKey = needle
        c.rankByUse = byUse
        c.rankRev = rev
        c.rankVal = out
        return out
    }

    // Same answer rankEntries() gives, as DesktopEntry objects.
    function rank(q) {
        return root.rankEntries(q).map(e => e.app)
    }

    // Higher is better; 0 means "doesn't match". Cheapest/most-likely
    // field checked first — an app whose *name* starts with what you
    // typed is almost always the one you meant, so that outranks a
    // hit buried in another app's long description. `needle` is already
    // lower-cased and trimmed.
    function scoreEntry(e, needle) {
        const name = e.nameL
        if (name === needle)
            return 100
        if (name.startsWith(needle))
            return 80
        if (name.includes(needle))
            return 60

        const generic = e.genericL
        if (generic.startsWith(needle))
            return 45
        if (generic.includes(needle))
            return 35

        if (e.keywordsL.includes(needle))
            return 25

        if (e.commentL.includes(needle))
            return 10

        return 0
    }

    // The icon file for an icon name, looked up once. Every tile asks for it, and
    // asking the icon theme costs a trip through its directories each time.
    // Forgotten whenever the list of apps is rebuilt.
    function iconFor(name) {
        if (!name)
            return ""
        const c = root._cache
        const src = root.entries
        // Forgotten after an icon theme change and whenever new icon files were looked up.
        const rev = IconCursorService.revision
        const res = IconCursorService.resolved
        if (c.iconSrc !== src || c.iconRev !== rev || c.iconRes !== res) {
            c.iconSrc = src
            c.iconRev = rev
            c.iconRes = res
            c.icons = ({})
        }
        let p = c.icons[name]
        if (p === undefined) {
            p = IconCursorService.path(name, true)
            c.icons[name] = p
        }
        return p
    }

    // Runs the app. Quickshell resolves the desktop entry's Exec line
    // (terminal wrapper, working directory, field codes) itself — see
    // DesktopEntry.execute() — so there's nothing to shell out to here.
    function launch(app) {
        if (!app)
            return
        app.execute()
        root.recordLaunch(app)
    }
}
