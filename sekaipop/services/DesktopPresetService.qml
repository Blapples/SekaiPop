pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/PresetParts.js" as PP
import "../modules/common/functions/Framing.js" as FR

// Desktop presets: save the whole look of the desktop under a name, wear it
// again with one click. They live on the PRESETS tab of Edit Desktop's shelf
// (EditPresetBoard.qml).
//
// How pC (end4's shell) does it, and what is the same here: a preset is a
// JSON file made from the shell's whole config; saving filters out what is
// personal or machine-specific (his BLACKLIST_FILTER in scripts/presets.sh),
// applying merges the file back over the live config. pC has ONE config file,
// so applying is a deep merge plus a theme refresh. This shell keeps its state
// in many small pieces (each service owns one and saves it on its own), so the
// same two steps look like this:
//
//   capture()   asks each piece for its look and puts them in one object
//   apply()     hands each piece its part back through the same setters the
//               Settings Panel and Edit Desktop use, so everything changes
//               LIVE (no restart) and each piece saves itself as usual
//
// What a preset holds:
//   settings    the Settings Panel's switches and numbers (SettingsService)
//               except the ones listed in `keepExact` / `keepPrefix` below
//   theme       the colour group and Light / Dark / Darker
//   bar         style, edge, and the left / centre / right arrangement
//   widgets     every desktop widget listed in PresetWidgets.qml (clock, user card, weather, to-do,
//               visualizer, calendar card, palette card, sticky notes, image frames): on or off,
//               where they sit, and their looks (the to-do TASKS, the calendar's events and the
//               palette's colours / favourites are not saved). The to-do also keeps its SIZE
//               (full / 2x2). The sticky notes: on / off in the preset's file; their TEXT, colours
//               and places belong to the preset but are kept by NotesService (one set of notes
//               per preset, switched when a preset is worn; the to-do's tasks are the same under
//               every preset, the notes are not). The custom pictures (Image
//               frames): on / off AND every frame, with its spot, size, crop and dress; the
//               pictures themselves are copied into <name>.frames/ beside <name>.json, because
//               the shell deletes a picture's file when its frame goes (see wearFrames()). A
//               preset saved before frames were part of one holds on / off only and leaves your
//               frames alone. A preset saved before a widget existed has no part for
//               it, and wearing that preset switches the widget OFF (it does not stay on from the
//               look you had before). That is one rule for every widget in PresetWidgets.qml
//               (PresetParts.js), so a NEW widget needs no code here: add its entry there. Same
//               for a NEW option of a widget (a style, a size, a direction): a preset saved before
//               it existed wears it as the entry's `before` says, whatever it is set to now.
//   quickPanel  which buttons the Quick Panel has, their sizes and columns
//   wallpaper   the desktop wallpaper (per monitor when that mode is on) and
//               the lockscreen's own, if it has one
//   dock        the dock's keys, in order: pinned apps, folders, separators and the built-in
//               tools (PinnedAppsService). A preset saved before this existed has no `dock`
//               part and leaves yours alone. The dock's own named layouts (its right-click
//               menu) are separate and are not part of a preset.
//   phone       the Quick Panel phone's style (2.5D or flat 2D) and its panel settings: hot edge
//               on / off, edge delay, peek first, type to search apps. They are Settings Panel keys, but
//               they sit in `keepExact` so an older preset can't reset them; this part is how a
//               preset carries them. A preset saved before it existed has no `phone` part and
//               leaves yours alone. (How much of the phone shows and the notification style
//               are plain settings and were always part of a preset.)
//   overview    the Overview's style (film strip or the Scroll plugin), the board's side of the
//               screen and how many workspace cards it shows, and the Scroll plugin's layout /
//               scale / gap (the ones the panel sets; "not set" stays "not set"). Same as
//               `phone`: Settings Panel keys held back by `keepPrefix` so an older preset can't
//               reset them, carried by this part instead; a preset saved before it existed has
//               no `overview` part and leaves yours alone.
//   lock        the lockscreen's style (Gacha or Calendar). `lock.style` is a Settings Panel key held
//               back by `keepExact` so an older preset can't reset it; this part carries it. A preset
//               saved before it existed has no `lock` part and leaves yours alone. (The Calendar's
//               other options, lock.tone / lock.crop / lock.powerButtons, stay yours under every preset.)
//   images      the avatar and banner (PanelImages.qml). pick-image.sh deletes
//               the old picture whenever a new one is picked, so a preset
//               keeps its OWN copy in <name>.images/ beside <name>.json
//               (preset-state.sh). Wearing a preset puts the copy back as the
//               avatar / banner. A preset saved with none wears "none" (the
//               default picture comes back); a preset saved before this
//               existed has no `images` part and leaves yours alone.
//
// What it never touches (so a preset from last month can't surprise you):
//   keepExact / keepPrefix   24-hour time, weather unit and place, calendar
//                            stars, what the dock's Files key runs, the clipboard
//                            and web-suggestion switches, update checks,
//                            Pomodoro times, the screenshot picker, the
//                            wallpaper video / thumbnail engine, app and system
//                            colour sync, Wallhaven's sort and filters in the
//                            Wallpapers picker (the Quick Panel phone's own style and
//                            settings are NOT here: they are the `phone` part below)
//   each widget's `skip`     (PresetWidgets.qml) the visualizer's audio engine and
//                            performance switches, the clock's 24-hour format, the
//                            calendar's events, the palette's colours
//   not in a preset at all   the shell scale per monitor,
//                            night light and other system toggles, "Lock all"
// Move a key between the lists and rebuild nothing else: both capture() and
// apply() read them.
//
// Favourites: a preset can be pinned (the star on its tile). Pinned presets stand
// first in the PRESETS tab, then the rest, each group by name. It is a flag in
// the preset's own file (`_meta.favorite`), so it travels with the folder, and it
// is not part of the look: it never affects the "you are wearing this one" tick.
//
// Undo: wearing a preset replaces the whole look at once, and each piece saves itself, so a
// stray click used to cost every setting it touched. Now:
//   wearing      first saves the look it replaces as the hidden preset ".previous"
//                (keepPrevious(): pictures, frames and the sticky notes too, on disk, so it
//                survives a restart). undoWear() wears it back, and the look it undoes takes
//                its place, so Undo again is Redo (the tile says so: `_meta.undone`). One
//                level only. Wearing a preset that is
//                already the look keeps the undo there was.
//   deleting     moves the preset into presets/.trash/ (its notes with it) instead of
//                removing it; undoRemove() brings it back. Only the last one deleted is
//                kept, for `trashMinutes`: then it is gone for good (and the UNDELETE tile
//                with it), at once or at the next start if the shell wasn't running.
// Both show as tiles on the PRESETS tab while there is something to undo.
//
// Files: ${XDG_CONFIG_HOME:-~/.config}/sekaipop/presets/<name>.json
// (scripts/state/preset-state.sh).
//
//   qs -c sekaipop ipc call presets list
//   qs -c sekaipop ipc call presets undo                   (back to the look before the last preset)
//   qs -c sekaipop ipc call presets undelete               (bring the last deleted preset back)
//   qs -c sekaipop ipc call presets save "Night desk"      (replaces one of that name)
//   qs -c sekaipop ipc call presets apply "Night desk"
//   qs -c sekaipop ipc call presets rename "Night desk" "Late desk"
//   qs -c sekaipop ipc call presets remove "Night desk"
//   qs -c sekaipop ipc call presets favorite "Night desk"  (pin it to the front; again to unpin)
//   qs -c sekaipop ipc call presets toggle                 (Edit Desktop on the PRESETS tab)
Singleton {
    id: root

    // ===== what a preset leaves alone =====
    readonly property var keepExact: [
        "time.use24h",
        "pictures.framing",    // belongs to each picture: the `images` part carries it (imageEntry)
        "notify.on",           // do-not-disturb is the person's, not the look's
        "notify.quietFullscreen", // so is "quiet while a window is fullscreen"
        "battery.alerts",      // and whether the low-battery warnings are on
        "weather.fahrenheit",
        "weather.location",
        "calendar.marks",
        "dock.filesCommand",
        "dock.filesMode",
        "dock.files.folder",
        "dock.files.view",
        "dock.files.sort",
        "dock.files.reverse",
        "dock.files.hidden",
        "dock.files.foldersFirst",
        "dock.files.modified",
        "files.chooser",
        "launcher.webSuggestions",
        "launcher.clipboard",
        "lock.style",
        "lock.crop",
        "lock.tone",
        "lock.powerButtons",
        "lock.sleepDesktop",
        "lock.animations",
        "settings.page",
        "lock.lyrics",
        "panel.hotEdge",
        "panel.hotDwell",
        "panel.hotPeek",
        "panel.typeToSearch",
        "quick.flat",
        "quick.phoneShadow",
        "tray.scroll",
        "discord.leftClick",
        "wallpaper.folder",
        "wallpaper.thumbs",
        "wallpaper.video",
        "wallpaper.mpvpaper",
        "wallpaper.videoPause",
        "wallpaper.videoResume"
    ]

    readonly property var keepPrefix: [
        "updates.",
        "idle.",
        "appFonts.",
        "wallhaven.",
        "focus.",
        "timer.",
        "region.",
        "overview.",
        "appTheme.",
        "systemTheme."
    ]

    // True for a Settings Panel key a preset never reads or writes.
    function keeps(key) {
        if (root.keepExact.indexOf(key) >= 0)
            return true
        for (const p of root.keepPrefix) {
            if (key.indexOf(p) === 0)
                return true
        }
        return false
    }

    // ===== the Quick Panel's buttons =====
    // QuickSource is not a singleton, so it reports its layout here (see its
    // Connections / onTilesChanged) and listens for quickTilesRequested.
    property var quickTiles: null
    property int quickColumns: 5

    signal quickTilesRequested(var tiles, int columns)

    function noteQuickTiles(list, columns) {
        root.quickTiles = list
        root.quickColumns = columns
    }

    // ===== capture =====
    // (The widgets are captured by PresetParts.capture(PresetWidgets.all); see capture().)

    function baseName(path) {
        return String(path).slice(String(path).lastIndexOf("/") + 1)
    }

    // The preset's note about one worn picture, or null when none is worn.
    // The extension is lower-cased like preset-state.sh does when it copies.
    function imageEntry(kind, path) {
        if (path === "")
            return null
        const from = root.baseName(path)
        const dot = from.lastIndexOf(".")
        const ext = dot >= 0 ? "." + from.slice(dot + 1).toLowerCase() : ""
        const entry = { file: kind + ext, from: from }
        // Its framing, when it has one (a centred picture adds nothing, so a preset saved
        // before framing existed still reads as the look you are wearing).
        const f = PanelImages.framingFor(kind)
        if (!FR.isCentred(f))
            entry.framing = { zoom: f.zoom, panX: f.panX, panY: f.panY }
        return entry
    }

    // The custom pictures: on / off, and (once the saved frames have been read back, or a
    // preset saved in the first second would hold none) every frame as it is now. Each
    // frame is the record ImageService keeps; `path` points at the picture's copy.
    function imagesPart() {
        const part = { shown: ImageService.shown }
        if (ImageService.loaded)
            part.items = ImageService.items.map(r => Object.assign({}, r))
        return part
    }

    // The picture files a preset's frames use, without repeats (an empty frame has none).
    function framePaths(data) {
        const items = data && data.widgets && data.widgets.images ? data.widgets.images.items : null
        if (!Array.isArray(items))
            return []
        const all = []
        for (const it of items) {
            if (it && typeof it.path === "string" && it.path !== "" && all.indexOf(it.path) < 0)
                all.push(it.path)
        }
        return all
    }

    // The Overview's style and options (see the `overview` part above).
    function overviewPart() {
        return {
            style: SettingsService.get("overview.style"),
            position: SettingsService.get("overview.position"),
            workspaces: SettingsService.get("overview.workspaces"),
            layout: SettingsService.get("overview.layout"),
            scale: SettingsService.get("overview.scale"),
            gap: SettingsService.get("overview.gap")
        }
    }

    function wearOverview(o) {
        if (!o || typeof o !== "object")
            return
        const oneOf = (v, list) => typeof v === "string" && list.indexOf(v) >= 0
        const num = (v, lo, hi) => typeof v === "number" && isFinite(v) ? Math.max(lo, Math.min(hi, v)) : null
        if (oneOf(o.style, ["board", "scroll"]))
            SettingsService.set("overview.style", o.style)
        if (oneOf(o.position, ["left", "center", "right"]))
            SettingsService.set("overview.position", o.position)
        const ws = num(o.workspaces, 1, 10)
        if (ws !== null)
            SettingsService.set("overview.workspaces", Math.round(ws))
        // The plugin's options: "" / 0 / -1 mean "not set here" and are worn as that.
        if (oneOf(o.layout, ["", "vertical", "horizontal"]))
            SettingsService.set("overview.layout", o.layout)
        if (typeof o.scale === "number" && isFinite(o.scale))
            SettingsService.set("overview.scale", o.scale <= 0 ? 0 : Math.max(0.1, Math.min(0.9, Math.round(o.scale * 100) / 100)))
        if (typeof o.gap === "number" && isFinite(o.gap))
            SettingsService.set("overview.gap", o.gap < 0 ? -1 : Math.max(0, Math.min(300, Math.round(o.gap))))
        // Put the plugin's options on the plugin now (a no-op when it is not loaded).
        ScrollOverviewService.applyConfig()
    }

    // The Quick Panel phone's style and panel settings (see the `phone` part above).
    function phonePart() {
        return {
            flat: SettingsService.flag("quick.flat"),
            hotEdge: SettingsService.flag("panel.hotEdge"),
            hotDwell: SettingsService.get("panel.hotDwell"),
            hotPeek: SettingsService.flag("panel.hotPeek"),
            typeToSearch: SettingsService.flag("panel.typeToSearch")
        }
    }

    function wearPhone(p) {
        if (!p || typeof p !== "object")
            return
        if (typeof p.flat === "boolean")
            SettingsService.set("quick.flat", p.flat)
        if (typeof p.hotEdge === "boolean")
            SettingsService.set("panel.hotEdge", p.hotEdge)
        if (typeof p.hotDwell === "number" && isFinite(p.hotDwell))
            SettingsService.set("panel.hotDwell", Math.max(40, Math.min(800, p.hotDwell)))
        if (typeof p.hotPeek === "boolean")
            SettingsService.set("panel.hotPeek", p.hotPeek)
        if (typeof p.typeToSearch === "boolean")
            SettingsService.set("panel.typeToSearch", p.typeToSearch)
    }

    // The lockscreen's style (see the `lock` part above).
    function lockPart() {
        return { style: SettingsService.get("lock.style") }
    }

    function wearLock(l) {
        if (!l || typeof l !== "object")
            return
        if (l.style === "gacha" || l.style === "calendar")
            SettingsService.set("lock.style", l.style)
    }

    function capture() {
        const settings = {}
        for (const k of Object.keys(SettingsService.values).sort()) {
            if (!root.keeps(k))
                settings[k] = SettingsService.values[k]
        }

        const out = {
            settings: settings,
            theme: { group: ThemeService.current, mode: ThemeService.mode },
            phone: root.phonePart(),
            overview: root.overviewPart(),
            lock: root.lockPart(),
            bar: {
                style: BarStyleService.style,
                position: BarPositionService.position,
                layout: JSON.parse(JSON.stringify(BarLayoutService.payload()))
            },
            widgets: PP.capture(PresetWidgets.all)
        }

        // Not before PinnedAppsService has read the saved layout, or a preset
        // saved in the first second would hold an empty dock.
        if (PinnedAppsService.layoutRead)
            out.dock = { items: PinnedAppsService.copy(PinnedAppsService.pinned) }

        if (root.quickTiles !== null) {
            out.quickPanel = {
                tiles: root.quickTiles.map(t => ({ id: t.id, size: t.size })),
                columns: root.quickColumns
            }
        }

        // Same for the avatar and banner: not before PanelImages has looked
        // for the ones from an earlier session. Each is null (none picked) or
        // { file, from }: `file` is the copy's name inside <name>.images/,
        // `from` the name the picture has in the data folder, which is how
        // "is this the one I'm wearing" knows it again (see wearImages()).
        if (PanelImages.loaded) {
            out.images = {
                avatar: root.imageEntry("avatar", PanelImages.avatarPath),
                banner: root.imageEntry("banner", PanelImages.bannerPath)
            }
        }

        // Not before the saved pictures have been read back, or a preset saved
        // in the first second would hold an empty wallpaper.
        if (WallpaperService.ready) {
            const w = {
                default: WallpaperService.defaultPath,
                screens: Object.assign({}, WallpaperService.screenPaths)
            }
            if (WallpaperService.lockDefaultPath !== "")
                w.lockDefault = WallpaperService.lockDefaultPath
            if (Object.keys(WallpaperService.lockScreenPaths).length > 0)
                w.lockScreens = Object.assign({}, WallpaperService.lockScreenPaths)
            out.wallpaper = w
        }
        return out
    }

    // ===== is this preset what the desktop looks like right now? =====
    // JSON with sorted keys, so two objects with the same content give the
    // same text whatever order their keys were made in.
    function stable(v) {
        if (Array.isArray(v))
            return "[" + v.map(x => root.stable(x)).join(",") + "]"
        if (v !== null && typeof v === "object") {
            return "{" + Object.keys(v).sort()
                .map(k => JSON.stringify(k) + ":" + root.stable(v[k])).join(",") + "}"
        }
        const j = JSON.stringify(v)
        return j === undefined ? "null" : j
    }

    // The desktop as of the last refreshLive(). The PRESETS tab refreshes it
    // once a second while it is showing, so the "this is the one you are
    // wearing" tick on a preset is true, not remembered.
    property string liveDigest: ""
    // The same with parts left out, for presets saved before those were part of one
    // (they lack that part and must still get their tick): the avatar / banner, the
    // dock, the image frames (an older preset holds on / off for the pictures only), the
    // phone's style and settings, the Overview's, and the lockscreen's style. Keyed by
    // variantKey(); every mix of the six is here.
    property var liveDigests: ({})

    function variantKey(noImages, noDock, noFrames, noPhone, noOverview, noLock) {
        return (noImages ? "i" : "-") + (noDock ? "d" : "-") + (noFrames ? "f" : "-")
            + (noPhone ? "p" : "-") + (noOverview ? "o" : "-") + (noLock ? "l" : "-")
    }

    function refreshLive() {
        const now = root.capture()
        const out = {}
        const B = [false, true]
        for (const noImages of B) for (const noDock of B) for (const noFrames of B)
        for (const noPhone of B) for (const noOverview of B) for (const noLock of B) {
            const rest = {}
            for (const k of Object.keys(now)) {
                if ((noImages && k === "images") || (noDock && k === "dock")
                        || (noPhone && k === "phone") || (noOverview && k === "overview")
                        || (noLock && k === "lock"))
                    continue
                rest[k] = now[k]
            }
            if (noFrames && rest.widgets && rest.widgets.images) {
                rest.widgets = Object.assign({}, rest.widgets,
                    { images: { shown: rest.widgets.images.shown } })
            }
            out[root.variantKey(noImages, noDock, noFrames, noPhone, noOverview, noLock)] = root.stable(rest)
        }
        root.liveDigests = out
        root.liveDigest = out[root.variantKey(false, false, false, false, false, false)]
    }

    function digestOf(data) {
        const c = {}
        for (const k of Object.keys(data)) {
            if (k !== "_meta")
                c[k] = data[k]
        }
        // The widgets are compared by the registry (PresetWidgets.qml): a widget the preset
        // has no part for counts as "off" (that is what wearing it does), and a key the
        // preset could not have held keeps the widget's own value.
        if (c.widgets && typeof c.widgets === "object")
            c.widgets = PP.digestWidgets(PresetWidgets.all, c.widgets)
        return root.stable(c)
    }

    function isCurrent(data) {
        const noImages = data.images === undefined
        const noDock = data.dock === undefined
        const pics = data.widgets && typeof data.widgets === "object" ? data.widgets.images : null
        const noFrames = !pics || typeof pics !== "object" || !Array.isArray(pics.items)
        const noPhone = data.phone === undefined
        const noOverview = data.overview === undefined
        const noLock = data.lock === undefined
        const live = root.liveDigests[root.variantKey(noImages, noDock, noFrames, noPhone, noOverview, noLock)] ?? ""
        return live !== "" && root.digestOf(data) === live
    }

    // The picture a preset is drawn with on its tile: the main monitor's
    // wallpaper when each monitor has its own, else the one wallpaper.
    function previewPath(d) {
        const w = d ? d.wallpaper : null
        if (!w || typeof w !== "object")
            return ""
        const main = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
        if (w.screens && typeof w.screens[main] === "string" && w.screens[main] !== "")
            return w.screens[main]
        return typeof w.default === "string" ? w.default : ""
    }

    // ===== the list =====
    // [{ name, data }], by name. `data` is the whole saved object.
    property var presets: []
    property bool loaded: false

    function find(name) {
        for (const p of root.presets) {
            if (p.name === name)
                return p
        }
        return null
    }

    function has(name) {
        const low = String(name).toLowerCase()
        return root.presets.some(p => p.name.toLowerCase() === low)
    }

    // A name that can be a file name: no slashes or control characters, no
    // leading dots, one space between words, 40 characters at most.
    function cleanName(raw) {
        return String(raw ?? "")
            .replace(/[\/\\\u0000-\u001f]/g, " ")
            .replace(/\s+/g, " ")
            .replace(/^[\s.]+/, "")
            .trim()
            .slice(0, 40)
            .trim()
    }

    // "Preset 1", "Preset 2", ... the first one nobody has taken.
    function freshName(base) {
        const b = root.cleanName(base) || "Preset"
        if (!root.has(b))
            return b
        for (let i = 2; i < 1000; i++) {
            const n = root.cleanName(b + " " + i)
            if (!root.has(n))
                return n
        }
        return b
    }

    // What a pretty first name for a new preset is.
    function suggestName() {
        for (let i = 1; i < 1000; i++) {
            const n = "Preset " + i
            if (!root.has(n))
                return n
        }
        return "Preset"
    }

    // ===== saving, replacing, deleting =====
    readonly property string script: Directories.script("state/preset-state.sh")

    // The name of the preset saved or worn last (this session). The tick on a
    // tile needs isCurrent() as well, so this alone never shows one.
    property string lastName: ""

    // Saves the desktop as a NEW preset: a name that is taken gets " 2", " 3"...
    // Returns the name it ended up with ("" when the name was empty).
    function saveNew(raw) {
        const clean = root.cleanName(raw)
        if (clean === "")
            return ""
        const name = root.freshName(clean)
        root.write(name)
        return name
    }

    // Saves the desktop over the preset of this name (or as a new one).
    function overwrite(name) {
        const clean = root.cleanName(name)
        if (clean === "")
            return
        const existing = root.presets.find(p => p.name.toLowerCase() === clean.toLowerCase())
        root.write(existing ? existing.name : clean)
    }

    function write(name) {
        const data = root.capture()
        data._meta = { name: name, saved: Date.now(), v: 1 }
        // Saving over a favourite keeps it a favourite.
        const old = root.find(name)
        if (old && root.isFavorite(old))
            data._meta.favorite = true
        root.lastName = name
        // The sticky notes on the desktop become this preset's own.
        NotesService.adoptSet(name)
        // The two paths are the pictures worn right now ("-" = none): the
        // script copies them into the preset's own folder.
        root.enqueue(["sh", root.script, "save", name, JSON.stringify(data),
            data.images && PanelImages.avatarPath !== "" ? PanelImages.avatarPath : "-",
            data.images && PanelImages.bannerPath !== "" ? PanelImages.bannerPath : "-"]
            // ...and the pictures the image frames show, copied beside it the same way.
            .concat(root.framePaths(data)))
        // The desktop is, by definition, what was just saved.
        root.refreshLive()
    }

    function isFavorite(p) {
        return !!p && !!p.data && !!p.data._meta && p.data._meta.favorite === true
    }

    // Pins a preset to the front (or lets it go). Rewrites its file through the
    // same `rename` job (old name = new name), so the pictures stay where they are.
    // Returns whether it is a favourite afterwards.
    function setFavorite(name, on) {
        const p = root.find(name)
        if (!p)
            return false
        const want = on === true
        if (root.isFavorite(p) === want)
            return want
        const data = JSON.parse(JSON.stringify(p.data))
        const meta = Object.assign({}, data._meta)
        if (want)
            meta.favorite = true
        else
            delete meta.favorite
        data._meta = meta
        root.presets = root.presets.map(q => q === p ? { name: p.name, data: data } : q).sort(root.byName)
        root.enqueue(["sh", root.script, "rename", p.name, p.name, JSON.stringify(data)])
        return want
    }

    function toggleFavorite(name) {
        return root.setFavorite(name, !root.isFavorite(root.find(name)))
    }

    // Deleting goes to the trash (one deep), so undoRemove() can bring it back.
    function remove(name) {
        const p = root.find(name)
        if (!p)
            return
        if (root.lastName === name)
            root.lastName = ""
        const notes = NotesService.setPart(name)
        NotesService.dropSet(name)
        root.trashed = { name: p.name, data: p.data, notes: notes, at: Date.now() }
        // The tile goes at once, so Undo can't be refused for a name still listed.
        root.presets = root.presets.filter(q => q !== p)
        root.enqueue(["sh", root.script, "trash", name].concat(notes ? [JSON.stringify(notes)] : []))
    }

    // ===== undo =====
    // The look the last preset replaced (the hidden ".previous"), or null.
    property var previous: null
    // The last preset deleted, { name, data, notes, at }, or null. `at` is when, in ms.
    property var trashed: null
    readonly property int trashMinutes: 10

    // Empties the trash when its time is up. The script checks the time it wrote itself
    // (a couple of seconds later than `at`, hence the slack).
    onTrashedChanged: {
        if (!root.trashed) {
            trashTimer.stop()
            return
        }
        trashTimer.interval = Math.max(0, root.trashed.at + root.trashMinutes * 60000 - Date.now()) + 3000
        trashTimer.restart()
    }

    Timer {
        id: trashTimer
        onTriggered: {
            root.trashed = null
            root.enqueue(["sh", root.script, "purge-trash", String(root.trashMinutes * 60)])
        }
    }

    // Saves the desktop as ".previous" before `target` goes on. Not when the desktop
    // already is `target`: wearing it changes nothing, and the undo there is stays.
    // `undone`: undoWear() is saving the look it undoes, so the tile says REDO.
    function keepPrevious(target, undone) {
        root.refreshLive()
        if (root.isCurrent(target))
            return
        const data = root.capture()
        // `last` / `notes`: what undoWear() needs that a preset doesn't hold (which preset
        // was worn, and the sticky notes themselves, see NotesService.lookPart()).
        data._meta = { name: "", saved: Date.now(), v: 1, last: root.lastName, notes: NotesService.lookPart() }
        if (undone === true)
            data._meta.undone = true
        root.previous = data
        root.enqueue(["sh", root.script, "save", ".previous", JSON.stringify(data),
            data.images && PanelImages.avatarPath !== "" ? PanelImages.avatarPath : "-",
            data.images && PanelImages.bannerPath !== "" ? PanelImages.bannerPath : "-"]
            .concat(root.framePaths(data)))
    }

    // Wears ".previous" back. It is renamed ".undone" first and worn from there, so the look
    // being undone can be saved as the new ".previous" (Undo again = Redo) without the two
    // sets of pictures meeting.
    function undoWear() {
        const d = root.previous
        if (!d || root.busy())
            return
        const meta = d._meta && typeof d._meta === "object" ? d._meta : {}
        const notes = meta.notes && typeof meta.notes === "object" ? meta.notes : null
        // A preset deleted since then gets neither the tick name nor the notes.
        const back = {
            notes: notes,
            set: notes && typeof notes.setName === "string" && root.find(notes.setName) ? notes.setName : "",
            last: typeof meta.last === "string" && root.find(meta.last) ? meta.last : ""
        }
        root.previous = null
        root.enqueue(["sh", root.script, "delete", ".undone"])
        root.enqueue(["sh", root.script, "rename", ".previous", ".undone", JSON.stringify(d)])
        root.keepPrevious(d, !(meta.undone === true))
        root.start(d, ".undone", back)
    }

    // Brings the last deleted preset back, its notes too. Returns its name, or "" (nothing
    // in the trash, or a preset of that name has been saved since).
    function undoRemove() {
        const t = root.trashed
        if (!t || root.has(t.name))
            return ""
        root.trashed = null
        NotesService.restoreSet(t.name, t.notes)
        root.presets = root.presets.concat([{ name: t.name, data: t.data }]).sort(root.byName)
        root.enqueue(["sh", root.script, "untrash", t.name])
        return t.name
    }

    // Gives a preset another name: its file, its pictures and the name saved
    // inside it. Returns the name it ended up with, or "" when it did nothing:
    // no such preset, an empty name, or a name another preset already has. (It
    // never adds " 2" the way saving does, since that would not be the name that
    // was typed.) The same name, or one that only changes capitals, is fine.
    function rename(oldName, raw) {
        const p = root.find(oldName)
        const clean = root.cleanName(raw)
        if (!p || clean === "")
            return ""
        if (clean === p.name)
            return clean
        const low = clean.toLowerCase()
        if (root.presets.some(q => q !== p && q.name.toLowerCase() === low))
            return ""

        const data = JSON.parse(JSON.stringify(p.data))
        data._meta = Object.assign({}, data._meta, { name: clean })

        NotesService.renameSet(p.name, clean)
        if (root.lastName === p.name)
            root.lastName = clean
        if (root.pendingName === p.name)
            root.pendingName = clean

        // The tile changes at once; the list is read again when the job is done.
        root.presets = root.presets.map(q => q === p ? { name: clean, data: data } : q).sort(root.byName)
        root.enqueue(["sh", root.script, "rename", p.name, clean, JSON.stringify(data)])
        return clean
    }

    // Jobs run one at a time, in order, so a save straight after a delete
    // can't overtake it. The list is read again once the queue is empty.
    property var queue: []

    function enqueue(argv) {
        root.queue = root.queue.concat([argv])
        root.pump()
    }

    function pump() {
        if (job.running || root.queue.length === 0)
            return
        const next = root.queue[0]
        root.queue = root.queue.slice(1)
        job.exec(next)
    }

    Process {
        id: job

        onExited: {
            root.pump()
            if (!job.running) {
                if (root.waiting)
                    root.proceed()
                root.refresh()
            }
        }
    }

    // ===== reading the list =====
    property bool listAgain: false

    function refresh() {
        if (lister.running) {
            root.listAgain = true
            return
        }
        lister.exec(["sh", root.script, "all"])
    }

    // The order of the tiles: favourites first, then by name, capitals ignored.
    function byName(a, b) {
        const fa = !!a.data && !!a.data._meta && a.data._meta.favorite === true
        const fb = !!b.data && !!b.data._meta && b.data._meta.favorite === true
        if (fa !== fb)
            return fa ? -1 : 1
        const x = a.name.toLowerCase()
        const y = b.name.toLowerCase()
        return x < y ? -1 : (x > y ? 1 : 0)
    }

    // The presets. The undo slots (names with a leading dot) are parseSlots()'.
    function parseList(text) {
        const out = []
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab <= 0)
                continue
            const name = line.slice(0, tab)
            if (name.charAt(0) === ".")
                continue
            try {
                const data = JSON.parse(line.slice(tab + 1))
                if (data && typeof data === "object" && !Array.isArray(data))
                    out.push({ name: name, data: data })
            } catch (e) {
                console.warn("DesktopPresetService: couldn't read preset \"" + name + "\" (" + e + ")")
            }
        }
        out.sort(root.byName)
        return out
    }

    // { previous, trashed } out of the same listing: ".previous", ".trash/<name>",
    // ".trash/.notes" and ".trash/.at" (preset-state.sh all). Either is null when it isn't
    // there. A trash with no time counts as old (it is purged at once).
    function parseSlots(text) {
        const out = { previous: null, trashed: null }
        let notes = null
        let at = 0
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab <= 0 || line.charAt(0) !== ".")
                continue
            const name = line.slice(0, tab)
            let data = null
            try {
                data = JSON.parse(line.slice(tab + 1))
            } catch (e) {
                continue
            }
            if (name === ".trash/.at") {
                if (typeof data === "number" && data > 0)
                    at = data * 1000
                continue
            }
            if (!data || typeof data !== "object" || Array.isArray(data))
                continue
            if (name === ".previous")
                out.previous = data
            else if (name === ".trash/.notes")
                notes = data
            else if (name.indexOf(".trash/") === 0 && name.length > 7)
                out.trashed = { name: name.slice(7), data: data }
        }
        if (out.trashed) {
            out.trashed.notes = notes
            out.trashed.at = at
        }
        return out
    }

    Process {
        id: lister

        stdout: StdioCollector {
            onStreamFinished: {
                root.presets = root.parseList(text)
                const slots = root.parseSlots(text)
                // While an undo is on its way the slots on disk are about to change: the
                // ones in memory are already what they will be.
                if (root.queue.length === 0 && !job.running) {
                    root.previous = slots.previous
                    root.trashed = slots.trashed
                }
                root.loaded = true
            }
        }

        onExited: {
            root.loaded = true
            if (root.listAgain) {
                root.listAgain = false
                root.refresh()
            }
        }
    }

    Component.onCompleted: {
        // A half-made widget entry is reported once here instead of failing quietly.
        for (const msg of PP.problems(PresetWidgets.all))
            console.warn("DesktopPresetService: " + msg)
        root.refresh()
    }

    // ===== wearing a preset =====
    // The wallpaper files a preset names, without repeats.
    function wallpaperPaths(w) {
        if (!w)
            return []
        const all = []
        if (typeof w.default === "string")
            all.push(w.default)
        if (typeof w.lockDefault === "string")
            all.push(w.lockDefault)
        for (const group of [w.screens, w.lockScreens]) {
            if (group && typeof group === "object") {
                for (const k of Object.keys(group)) {
                    if (typeof group[k] === "string")
                        all.push(group[k])
                }
            }
        }
        return all.filter((p, i) => p !== "" && all.indexOf(p) === i)
    }

    property var pendingData: null
    property string pendingName: ""
    // Set when undoWear() is wearing ".previous" back: { notes, set, last } (see wear()).
    property var pendingBack: null
    // A preset is waiting for the job queue (the look it replaces is being saved).
    property bool waiting: false

    function busy() {
        return LockState.locked || root.waiting || checker.running || imager.running || framer.running
            || swap.running || comeBack.running
    }

    // Puts the preset on, after saving the look it replaces (keepPrevious()). The waits
    // are for that save, which copies the avatar / banner / frame pictures that wearing
    // the preset then deletes, and for the wallpaper files to be checked (a moment):
    // everything else changes at once, in the order that keeps the transitions from
    // blending twice (switches first, because "one wallpaper per monitor" decides how
    // the wallpaper is applied).
    function apply(name) {
        const p = root.find(name)
        if (!p || root.busy())
            return
        root.keepPrevious(p.data)
        root.start(p.data, name, null)
    }

    // `name` is the file the preset's pictures are in; `back` is undoWear()'s.
    function start(d, name, back) {
        root.pendingData = d
        root.pendingName = name
        root.pendingBack = back
        root.waiting = true
        if (!job.running && root.queue.length === 0)
            root.proceed()
    }

    function proceed() {
        root.waiting = false
        if (!root.pendingData)
            return
        const paths = root.wallpaperPaths(root.pendingData.wallpaper)
        if (paths.length === 0) {
            root.finishApply({})
            return
        }
        checker.exec(["sh", root.script, "exists"].concat(paths))
    }

    Process {
        id: checker

        stdout: StdioCollector {
            onStreamFinished: {
                const found = {}
                for (const line of text.split("\n")) {
                    if (line !== "")
                        found[line] = true
                }
                root.finishApply(found)
            }
        }
    }

    // ===== the motion of wearing a preset =====
    // Which of the bar, the dock and the widgets (a new variant, or switched off) this
    // preset is going to change, so only those slide / shrink away and come back (PresetMotion.qml).
    // The widgets glide to their new spots on their own and need no plan.
    function motionPlan(d) {
        let now = null
        try {
            now = root.capture()
        } catch (e) {
            return { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }
        }
        const mine = (d.settings && typeof d.settings === "object") ? d.settings : {}
        const keysChanged = prefix => {
            for (const k of Object.keys(mine)) {
                if (k.indexOf(prefix) !== 0 || root.keeps(k))
                    continue
                if (root.stable(mine[k]) !== root.stable(now.settings[k]))
                    return true
            }
            return false
        }
        const bar = (d.bar && typeof d.bar === "object" && root.stable(d.bar) !== root.stable(now.bar))
            || keysChanged("bar.")

        // A widget switching to another variant (the clock's design; the weather
        // card's style; the visualizer's style, colours, size or direction). Not for one that is
        // hidden before or after: showing and hiding have their own pop in /
        // swallow.
        const wmine = (d.widgets && typeof d.widgets === "object") ? Object.assign({}, d.widgets) : {}
        // An option a preset saved before it existed can't hold is what it was before (the
        // widget's `before` in PresetWidgets.qml), the same as when the preset is worn.
        for (const e of PresetWidgets.all) {
            if (wmine[e.id] && typeof wmine[e.id] === "object")
                wmine[e.id] = PP.readPart(e, wmine[e.id])
        }
        const wnow = (now.widgets && typeof now.widgets === "object") ? now.widgets : {}
        const varies = (name, keys) => {
            const a = wmine[name]
            const b = wnow[name]
            if (!a || typeof a !== "object" || !b || typeof b !== "object")
                return false
            if (a.shown === false || b.shown === false)
                return false
            for (const k of keys) {
                if (k in a && root.stable(a[k]) !== root.stable(b[k]))
                    return true
            }
            return false
        }

        // A widget the preset switches off (it is showing now): it shrinks away
        // with the rest instead of being swallowed after them. One the preset
        // switches on keeps its pop in.
        const turnsOff = name => {
            const a = wmine[name]
            const b = wnow[name]
            return !!a && typeof a === "object" && a.shown === false
                && !!b && typeof b === "object" && b.shown !== false
        }
        return {
            bar: bar === true,
            dock: keysChanged("dock.")
                || (!!d.dock && typeof d.dock === "object" && root.stable(d.dock) !== root.stable(now.dock)),
            clock: varies("clock", ["design"]) || turnsOff("clock"),
            visualizer: varies("visualizer", ["style", "colors", "size", "vertical"]) || turnsOff("visualizer"),
            usercard: turnsOff("usercard"),
            weathercard: varies("weathercard", ["style"]) || turnsOff("weathercard"),
            todo: turnsOff("todo")
        }
    }

    property var swapData: null
    property string swapName: ""
    property var swapBack: null
    property var swapFound: ({})

    // The bar / dock are off their edge by now: put the preset on, then bring
    // them back a moment later (the time a rebuilt window needs to exist).
    Timer {
        id: swap
        interval: PresetMotion.outMs + 40
        onTriggered: {
            const d = root.swapData
            root.swapData = null
            if (d)
                root.wear(d, root.swapName, root.swapFound, root.swapBack)
            comeBack.restart()
        }
    }

    Timer {
        id: comeBack
        interval: 140
        onTriggered: PresetMotion.release()
    }

    function finishApply(found) {
        const d = root.pendingData
        const name = root.pendingName
        const back = root.pendingBack
        root.pendingData = null
        root.pendingName = ""
        root.pendingBack = null
        if (!d)
            return

        const plan = root.motionPlan(d)
        if (!Object.keys(plan).some(k => plan[k] === true)) {
            root.wear(d, name, found, back)
            return
        }
        root.swapData = d
        root.swapName = name
        root.swapBack = back
        root.swapFound = found
        PresetMotion.begin(plan)
        swap.restart()
    }

    // `back` (undoWear()) wears ".previous": its notes and its tick go to the preset that
    // was worn then, not to `name`, which is only where its pictures are.
    function wear(d, name, found, back) {
        // 1. The Settings Panel's switches (and the per-monitor wallpaper mode).
        if (d.settings && typeof d.settings === "object")
            SettingsService.applyPreset(d.settings, root.keeps)

        // 1b. The Quick Panel phone's style and settings, and the Overview's. A preset without
        // that part (saved before it was one) leaves them alone.
        root.wearPhone(d.phone)
        root.wearOverview(d.overview)
        root.wearLock(d.lock)

        // 2. Colours.
        if (d.theme) {
            if (typeof d.theme.group === "string")
                ThemeService.setTheme(d.theme.group)
            if (d.theme.mode === "light" || d.theme.mode === "dark" || d.theme.mode === "darker")
                ThemeService.setModeAndSystem(d.theme.mode)
        }

        // 3. The bar.
        if (d.bar) {
            if (typeof d.bar.style === "string")
                BarStyleService.setStyle(d.bar.style)
            if (typeof d.bar.position === "string")
                BarPositionService.setPosition(d.bar.position)
            if (d.bar.layout && typeof d.bar.layout === "object")
                BarLayoutService.applyPayload(d.bar.layout)
        }

        // 3b. The sticky notes: this preset's own come back (before the widgets, so the
        // notes' on / off below applies to them).
        if (back)
            NotesService.wearLook(back.notes, back.set)
        else
            NotesService.switchSet(name)

        // 4. The widgets, all through the registry (PresetWidgets.qml). A preset that holds
        // a widget wears it; one saved before the widget existed has no part for it, so the
        // widget is switched OFF instead of staying on from the look you had before.
        PP.wear(PresetWidgets.all, d.widgets, {
            name: name,
            // The image frames' pictures come back out of the preset's folder first.
            wearFrames: items => root.wearFrames(name, items)
        })

        // 4b. The dock's keys. A preset without a `dock` part (saved before it
        // was one) leaves the dock alone.
        if (d.dock && typeof d.dock === "object" && Array.isArray(d.dock.items)) {
            const items = d.dock.items.filter(it => it && typeof it === "object")
            PinnedAppsService.commit(PinnedAppsService.copy(items))
        }

        // 5. Avatar and banner.
        root.wearImages(name, d.images)

        // 6. The Quick Panel's buttons.
        if (d.quickPanel && Array.isArray(d.quickPanel.tiles))
            root.quickTilesRequested(d.quickPanel.tiles, d.quickPanel.columns)

        // 7. Wallpaper, last: the colours above are already the new ones when
        // its transition starts, and with matugen the palette follows it.
        root.applyWallpaper(d.wallpaper, found)

        root.lastName = back ? back.last : name
        liveTimer.restart()
    }

    // Puts a preset's avatar and banner on. `images` is the preset's `images`
    // part: missing altogether (an older preset) = leave both alone; a kind
    // that is null = that preset had none, so go back to the default picture;
    // otherwise copy the preset's own picture out into the data folder. A
    // picture the preset names that is already worn is not copied again, and
    // one whose copy has been deleted just stays as it is.
    function wearImages(name, images) {
        if (!images || typeof images !== "object")
            return
        const args = []
        for (const kind of ["avatar", "banner"]) {
            if (!(kind in images))
                continue
            const img = images[kind]
            const worn = kind === "avatar" ? PanelImages.avatarPath : PanelImages.bannerPath
            if (img === null) {
                if (worn !== "")
                    PanelImages.clear(kind)
                continue
            }
            if (typeof img !== "object" || typeof img.file !== "string" || img.file === "")
                continue
            const from = typeof img.from === "string" ? img.from : ""
            // The framing that comes with it (none: centred, as a preset from before framing).
            const framing = img.framing && typeof img.framing === "object" ? img.framing : null
            if (from !== "" && root.baseName(worn) === from) {
                // Already this picture: only its framing may differ.
                PanelImages.setFraming(kind, framing)
                continue
            }
            root.pendingFraming[kind] = framing
            args.push(kind, img.file, from)
        }
        if (args.length > 0)
            imager.exec(["sh", root.script, "restore", name].concat(args))
    }

    // preset-state.sh restore prints "<kind> <path>" for each picture it put
    // in the data folder; PanelImages shows them from there on.
    Process {
        id: imager

        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const sp = line.indexOf(" ")
                    if (sp > 0) {
                        const kind = line.slice(0, sp)
                        PanelImages.assign(kind, line.slice(sp + 1))
                        // The copy came back under a new name: frame that one.
                        if (kind in root.pendingFraming) {
                            PanelImages.setFraming(kind, root.pendingFraming[kind])
                            delete root.pendingFraming[kind]
                        }
                    }
                }
            }
        }
    }

    // The framing of each picture a preset is putting back, until its copy is in place.
    property var pendingFraming: ({})

    // Puts a preset's image frames on. The pictures come back out of <name>.frames/ into the
    // data folder first (preset-state.sh restore-frames prints where each one is now; one
    // whose copy is gone is left out), then ImageService swaps its frames for them.
    property var framesJob: null

    function wearFrames(name, items) {
        const list = items.filter(it => it && typeof it === "object")
        const files = []
        for (const it of list) {
            if (typeof it.path !== "string" || it.path === "")
                continue
            const b = root.baseName(it.path)
            if (files.indexOf(b) < 0)
                files.push(b)
        }
        if (files.length === 0) {
            ImageService.wearFrames(list, {})
            return
        }
        root.framesJob = list
        framer.exec(["sh", root.script, "restore-frames", name].concat(files))
    }

    Process {
        id: framer

        stdout: StdioCollector {
            onStreamFinished: {
                const where = {}
                for (const line of text.split("\n")) {
                    if (line !== "")
                        where[root.baseName(line)] = line
                }
                const list = root.framesJob
                root.framesJob = null
                if (list) {
                    ImageService.wearFrames(list, where)
                    root.refreshLive()
                }
            }
        }
    }

    function screenExists(name) {
        return Quickshell.screens.some(s => s.name === name)
    }

    function applyWallpaper(w, found) {
        if (!w || typeof w !== "object")
            return
        const ok = p => typeof p === "string" && p !== "" && found[p] === true

        const picks = []
        if (WallpaperService.perMonitor && w.screens && typeof w.screens === "object") {
            for (const n of Object.keys(w.screens)) {
                if (root.screenExists(n) && ok(w.screens[n]))
                    picks.push({ screen: n, path: w.screens[n] })
            }
        }
        // With one wallpaper per monitor each monitor gets its own picture in
        // ONE step (the default as well first would blend twice).
        if (picks.length > 0) {
            for (const p of picks)
                WallpaperService.setWallpaper(p.path, p.screen)
        } else if (ok(w.default)) {
            WallpaperService.setWallpaper(w.default)
        } else if (root.wallpaperPaths(w).length > 0) {
            Quickshell.execDetached(["notify-send", "-a", "Presets", "-i", "material:image_not_supported", "Wallpaper not found",
                "The preset's wallpaper file is gone, so the wallpaper stays as it is."])
        }

        if (typeof w.lockDefault === "string" && ok(w.lockDefault))
            WallpaperService.setLockWallpaper(w.lockDefault)
        if (WallpaperService.perMonitor && w.lockScreens && typeof w.lockScreens === "object") {
            for (const n of Object.keys(w.lockScreens)) {
                if (root.screenExists(n) && ok(w.lockScreens[n]))
                    WallpaperService.setLockWallpaper(w.lockScreens[n], n)
            }
        }
    }

    // Looks again at what the desktop is, a moment after a preset went on
    // (the services save and settle asynchronously), so its tick comes up.
    Timer {
        id: liveTimer
        interval: 700
        onTriggered: root.refreshLive()
    }

    // ===== Edit Desktop's PRESETS tab =====
    function toggleBoard() {
        if (EditMode.active) {
            if (EditMode.currentTab === "presets")
                EditMode.close()
            else
                EditMode.showTab("presets")
            return
        }
        EditMode.open("", "presets")
    }

    function openBoard() {
        if (!EditMode.active)
            EditMode.open("", "presets")
        else if (EditMode.currentTab !== "presets")
            EditMode.showTab("presets")
    }

    IpcHandler {
        target: "presets"

        function list(): string {
            return root.presets.map(p => p.name).join("\n")
        }

        function save(name: string): void {
            root.overwrite(name)
        }

        function apply(name: string): void {
            root.apply(name)
        }

        function remove(name: string): void {
            root.remove(name)
        }

        function undo(): void {
            root.undoWear()
        }

        function undelete(): string {
            return root.undoRemove()
        }

        function rename(name: string, to: string): string {
            return root.rename(name, to)
        }

        function favorite(name: string): string {
            if (!root.find(name))
                return ""
            return root.toggleFavorite(name) ? "favorite" : "not favorite"
        }

        function toggle(): void {
            root.toggleBoard()
        }

        function open(): void {
            root.openBoard()
        }
    }
}
