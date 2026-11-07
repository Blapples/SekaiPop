pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import "../modules/common/functions/ShelfDragMath.js" as SDM

// Edit Desktop's state — one singleton, so every window that has to take
// part (the wallpaper, the clock and to-do widgets, the shelf, the
// right-click menu) reads the same few numbers instead of talking to each
// other.
//
// What the mode does, in one picture: the desktop (wallpaper + widgets + the
// bar and the dock) shrinks into a framed sticker card in the middle of the screen, the rest
// of the screen becomes a dark diamond-pattern stage, and a shelf (EditTray.qml)
// slides up from the bottom edge. The shelf shows every desktop widget as it
// really looks (a live snapshot of the widget's own card, see EditPreview.qml).
//
//   - left click a widget on the shelf   add it to the desktop (or, if it is
//                                        already there, select it for editing)
//   - left click a widget on the card    select it to EDIT it: it works like it
//                                        does on the normal desktop (the clock's
//                                        double-click and style button, the
//                                        To-Do's tasks, the avatar), and it can
//                                        still be dragged
//   - left drag a widget on the card     move it
//   - right click a widget (card or shelf)   remove it
//   - click the bare card, or Esc        stop editing the selected widget
//   - Done (or Esc again)                leave
//
// How the shrinking is shared: each window draws its own piece of the
// desktop, so each one applies the SAME transform, worked out here from the
// same `progress`. `progress` is the one animated number (0 = the normal
// desktop, 1 = the card); the rest of this file is arithmetic on it.
//
//   EditMode.open("DP-1")      start editing that monitor (not while an application is on its
//                              active workspace: a notice says to go to an empty one)
//   EditMode.close()
//   EditMode.openMenu(screen, x, y)   the right-click menu (DesktopMenu.qml)
//
//   qs -c sekaipop ipc call desktopedit toggle   (also: open / close)
//
// "Lock all" (see below): a saved switch, changed from the shelf's tile. It
// decides whether widgets can be dragged on the normal desktop; while editing
// it is ignored.
//
// The windows it is read from: WallpaperLayer.qml (backdrop + frame),
// EditStage.qml (wraps the widget, bar and dock windows' content),
// EditChrome.qml (the outline / drag shield / right-click remove),
// EditPreview.qml (each widget's snapshot for the shelf), EditTray.qml +
// EditTraySlot.qml (the shelf), DesktopMenu.qml.
//
// The bar and the dock draw through an EditStage too. Their windows are as
// big as the screen across their strip and never change size (resizing a
// layer-shell window that is anchored to the bottom or right edge shows its
// old picture in the wrong place for a frame or two, which is what made them
// jump when the mode started and ended); only their input region is the strip,
// and it is emptied while editing: in the card they are pictures.
Singleton {
    id: root

    // ===== state =====
    property bool active: false
    // The monitor being edited. Stays set while the card grows back to a
    // full desktop, so the windows can finish their exit animation.
    property string screenName: ""
    // 0 = normal desktop .. 1 = the card (overshoots a little on the way in).
    property real progress: 0

    // ===== the right-click menu =====
    property bool menuOpen: false
    property string menuScreen: ""
    property real menuX: 0           // window pixels, from the screen's top-left
    property real menuY: 0

    // ===== layout =====
    readonly property real trayHeight: 220       // the strip the shelf takes, gap included
    readonly property real frameWidth: 14        // navy outline + white ring around the card
    readonly property real cardRadius: 22        // the card's own corner
    readonly property real gap: 22               // space between the frame and whatever is next to it

    // Edit Desktop is on EVERY monitor at once: `screenName` is the one it was opened on (the
    // main one: it has the shelf and the bar editor), `sharedScreens` are the others. They all
    // shrink to a card and their widgets can be dragged, each on its own monitor.
    property var sharedScreens: []

    function editing(name) {
        if (root.screenName === "")
            return false
        return root.screenName === name || root.sharedScreens.indexOf(name) >= 0
    }

    // Make another monitor the main one while editing: the shelf goes there.
    function setMain(name) {
        if (!root.active || root.screenName === "" || name === root.screenName || !root.screenPlugged(name))
            return false
        root.menuOpen = false
        root.editTarget = ""
        root.sharedScreens = root.otherScreens(name)
        root.screenName = name
        return true
    }

    function otherScreens(main) {
        const out = []
        for (const s of Quickshell.screens) {
            if (s.name !== main)
                out.push(s.name)
        }
        return out
    }

    // ===== the shelf's tab =====
    property string requestedTab: "widgets"
    property int tabSerial: 0
    property string currentTab: "widgets"

    function showTab(tab) {
        root.requestedTab = tab
        root.tabSerial = root.tabSerial + 1
    }

    // `ipc call desktopedit matugen` asked for the Matugen theme's controls. The THEME tab
    // (EditThemeBoard.qml) takes them up and clears this once it is showing; it is a flag, not
    // a signal, because the shelf is only built when Edit Desktop opens.
    property bool matugenAsked: false

    function openMatugen() {
        if (!ThemeService.matugenInstalled)
            return
        if (ThemeService.current !== "matugen")
            ThemeService.setTheme("matugen")
        root.matugenAsked = true
        if (root.active)
            root.showTab("theme")
        else
            root.open("", "theme")
    }

    // ===== the selected widget =====
    property string editTarget: ""

    function select(id) {
        root.editTarget = (root.active && typeof id === "string") ? id : ""
    }

    // A one-shot "look here": the widget with this id flashes its outline
    // (EditChrome.qml listens to pingSerial).
    property string pingId: ""
    property int pingSerial: 0

    function ping(id) {
        root.pingId = id
        root.pingSerial = root.pingSerial + 1
    }

    // ===== what each widget looks like =====
    property var previewUrls: ({})
    property var previewSizes: ({})

    function setPreview(id, url, w, h) {
        const u = Object.assign({}, root.previewUrls)
        const z = Object.assign({}, root.previewSizes)
        if (url === "") {
            delete u[id]
            delete z[id]
        } else {
            u[id] = url
            z[id] = { w: w, h: h }
        }
        root.previewUrls = u
        root.previewSizes = z
    }

    // ===== the widgets =====
    readonly property var widgetList: [
        { id: "clock", title: "Clock", icon: "schedule" },
        { id: "usercard", title: "User card", icon: "badge" },
        { id: "weathercard", title: "Weather", icon: "partly_cloudy_day" },
        { id: "calendarcard", title: "Calendar", icon: "calendar_month" },
        { id: "todo", title: "To-Do", icon: "checklist" },
        { id: "notes", title: "Sticky Notes", icon: "sticky_note_2" },
        { id: "visualizer", title: "Visualizer", icon: "graphic_eq" },
        // Not one widget but a way to make them: it is never "on the desktop", so a click
        // always adds another frame, an EMPTY one that is on the desktop at once (nothing
        // is asked first; files are dropped on it, see ImageWidget.qml). Each picture on
        // the desktop is then its own id, "image:<id>", edited and removed like the
        // others, though it has no tile of its own.
        { id: "image", title: "Image", icon: "add_photo_alternate" },
        { id: "palettecard", title: "Palette", icon: "palette" },
        { id: "lyrics", title: "Lyrics", icon: "lyrics" },
        { id: "watertank", title: "Water tank", icon: "water_drop" },
        { id: "downloader", title: "Downloader", icon: "download" }
    ]

    // What the shelf shows: the widgets above, then the desktop widget plugins that loaded
    // (services/PluginService.qml), as "plugin:<id>". Everything below handles a plugin
    // through its PluginState, which has the same shape as a widget's service.
    readonly property var shelfList: root.widgetList.concat(PluginService.shelfEntries)

    // The monitor a widget really lives on: the one it was last dropped on, or
    // the first one if that is not plugged in (or it never was dropped).
    function homeScreen(saved) {
        for (const s of Quickshell.screens) {
            if (s.name === saved)
                return saved
        }
        // (the monitor chosen as the default one, else the first: DesktopMonitors.qml)
        return DesktopMonitors.fallbackName
    }

    // ===== one widget, several monitors =====
    // A widget has one MAIN copy (the one its service knows: screenName, posX, posY) and, when it
    // is added on another monitor, a copy there with a spot of its own (WidgetClones.qml). Adding
    // a widget on a monitor that already has it elsewhere makes a copy instead of moving it, and
    // removing it takes it off THIS monitor only. Not the visualizer (it can be a band along an
    // edge), the To-Do or the Sticky Notes (one monitor, chosen in Settings → Desktop → Widgets or by
    // adding them while editing that monitor: DesktopMonitors.qml); a picture is already
    // its own widget on its own monitor.
    readonly property var cloneIds: ["clock", "usercard", "weathercard", "calendarcard", "palettecard", "lyrics"]

    function cloneable(id) {
        if (PluginService.isPluginId(id)) {
            const p = PluginService.pluginOf(id)
            return !!p && p.cloneable
        }
        return root.cloneIds.indexOf(id) >= 0
    }

    function svcOf(id) {
        if (id === "clock")
            return ClockService
        if (id === "usercard")
            return UserCardService
        if (id === "weathercard")
            return WeatherCardService
        if (id === "calendarcard")
            return CalendarCardService
        if (id === "palettecard")
            return PaletteService
        if (id === "lyrics")
            return LyricsService
        if (PluginService.isPluginId(id))
            return PluginService.stateFor(id)
        return null
    }

    // The monitor the main copy is on.
    function homeOf(id) {
        const s = root.svcOf(id)
        return s ? root.homeScreen(s.screenName) : ""
    }

    function screenPlugged(name) {
        for (const s of Quickshell.screens) {
            if (s.name === name)
                return true
        }
        return false
    }

    // The shelf's tile was clicked on monitor `here`.
    function addCloneable(id, here) {
        const svc = root.svcOf(id)
        if (!svc || here === "")
            return
        if (root.widgetShown(id)) {
            // Already here (the main copy or a copy): nothing to add, the click just selects it.
            if (root.homeOf(id) === here || WidgetClones.has(id, here))
                return
            // On another monitor: this one gets a copy, with a spot of its own.
            WidgetClones.add(id, here)
            return
        }
        // Switched off: it comes back here, at its first spot (what a new widget always did).
        if (root.homeOf(id) !== here) {
            svc.posX = -1
            svc.posY = -1
            svc.screenName = here
        }
        WidgetClones.remove(id, here)
        WidgetClones.rebuild()
        svc.setShown(true)
    }

    // Take the widget off monitor `here` (the right click). The last monitor it is on switches it
    // off. When it is the main copy that goes and there are copies, one of them becomes the main
    // copy (it keeps its spot).
    function removeFrom(id, here) {
        const svc = root.svcOf(id)
        if (!svc)
            return
        if (root.editTarget === id)
            root.editTarget = ""
        if (root.homeOf(id) !== here) {
            WidgetClones.remove(id, here)
            return
        }
        // (a copy saved for the monitor the main copy is on is a leftover)
        WidgetClones.remove(id, here)
        const others = WidgetClones.screens[id] || []
        if (others.length === 0) {
            svc.setShown(false)
            return
        }
        const to = others[0]
        const p = WidgetClones.spot(id, to)
        WidgetClones.remove(id, to)
        svc.setPosition(p ? p.x : -1, p ? p.y : -1, to, p ? p.scale : 0)
        WidgetClones.rebuild()
    }

    // `ipc call desktopedit movewidget <id> <monitor>`: the widget's copy on the monitor being
    // edited (or the focused one) goes to <monitor>, to a first spot there. If <monitor> has it
    // already, it is just taken off this one.
    function moveWidget(id, to) {
        if (!root.cloneable(id) || !root.screenPlugged(to) || !root.widgetShown(id))
            return false
        const from = root.screenName !== "" ? root.screenName : root.focusedScreenName()
        if (from === "" || from === to)
            return false
        const isMain = root.homeOf(id) === from
        if (!isMain && !WidgetClones.has(id, from))
            return false
        const there = root.homeOf(id) === to || WidgetClones.has(id, to)
        if (there) {
            root.removeFrom(id, from)
            return true
        }
        if (isMain) {
            const svc = root.svcOf(id)
            svc.posX = -1
            svc.posY = -1
            svc.setPosition(-1, -1, to, 0)
        } else {
            WidgetClones.remove(id, from)
            WidgetClones.add(id, to)
        }
        WidgetClones.rebuild()
        return true
    }

    function widgetShown(id) {
        if (id === "clock")
            return ClockService.shown
        if (id === "usercard")
            return UserCardService.shown
        if (id === "weathercard")
            return WeatherCardService.shown
        if (id === "calendarcard")
            return CalendarCardService.shown
        if (id === "palettecard")
            return PaletteService.shown
        if (id === "lyrics")
            return LyricsService.shown
        if (id === "todo")
            return TodoService.shown
        if (id === "notes")
            return NotesService.active
        if (id === "visualizer")
            return VisualizerService.shown
        if (id === "watertank")
            return WaterTankService.shown
        if (id === "downloader")
            return DownloaderService.shown
        if (id === "image")
            return ImageService.shown
        if (id.indexOf("image:") === 0)
            return ImageService.shown && ImageService.rec(id.slice(6)) !== null
        if (PluginService.isPluginId(id)) {
            const st = PluginService.stateFor(id)
            return !!st && st.shown
        }
        return false
    }

    // On the card being edited right now: switched on AND on this monitor.
    function widgetOn(id) {
        if (!root.widgetShown(id) || root.screenName === "")
            return false
        // These can be on several monitors: here when this monitor has the main copy or a copy.
        if (root.cloneable(id))
            return root.homeOf(id) === root.screenName || WidgetClones.has(id, root.screenName)
        if (id === "clock")
            return root.homeScreen(ClockService.screenName) === root.screenName
        if (id === "usercard")
            return root.homeScreen(UserCardService.screenName) === root.screenName
        if (id === "weathercard")
            return root.homeScreen(WeatherCardService.screenName) === root.screenName
        if (id === "calendarcard")
            return root.homeScreen(CalendarCardService.screenName) === root.screenName
        if (id === "palettecard")
            return root.homeScreen(PaletteService.screenName) === root.screenName
        if (id === "lyrics")
            return root.homeScreen(LyricsService.screenName) === root.screenName
        if (id === "visualizer")
            return root.homeScreen(VisualizerService.screenName) === root.screenName
        if (id === "watertank")
            return root.homeScreen(WaterTankService.screenName) === root.screenName
        if (id === "downloader")
            return root.homeScreen(DownloaderService.screenName) === root.screenName
        // The shelf's Image tile is a button, not a widget: it is never "placed".
        if (id === "image")
            return false
        if (id.indexOf("image:") === 0) {
            const r = ImageService.rec(id.slice(6))
            return r !== null && root.homeScreen(r.screen) === root.screenName
        }
        // The To-Do card and the Sticky Notes are on the monitor chosen for them.
        if (id === "todo" || id === "notes")
            return DesktopMonitors.homeFor(id) === root.screenName
        // A plugin that stays on one monitor (its manifest says `cloneable: false`).
        if (PluginService.isPluginId(id)) {
            const st = PluginService.stateFor(id)
            return !!st && root.homeScreen(st.screenName) === root.screenName
        }
        return root.homeScreen("") === root.screenName
    }

    // Brings a widget onto the card. One that lives on another monitor is moved
    // here (and goes back to its first spot, which is on screen here: the
    // clock's is the right edge, vertically centred).
    function addWidget(id) {
        const here = root.screenName
        if (root.cloneable(id)) {
            root.addCloneable(id, here)
            return
        }
        if (id === "clock") {
            if (here !== "" && root.homeScreen(ClockService.screenName) !== here) {
                ClockService.posX = -1
                ClockService.posY = -1
                ClockService.screenName = here
            }
            ClockService.setShown(true)
        } else if (id === "usercard") {
            if (here !== "" && root.homeScreen(UserCardService.screenName) !== here) {
                UserCardService.posX = -1
                UserCardService.posY = -1
                UserCardService.screenName = here
            }
            UserCardService.setShown(true)
        } else if (id === "weathercard") {
            if (here !== "" && root.homeScreen(WeatherCardService.screenName) !== here) {
                WeatherCardService.posX = -1
                WeatherCardService.posY = -1
                WeatherCardService.screenName = here
            }
            WeatherCardService.setShown(true)
        } else if (id === "calendarcard") {
            if (here !== "" && root.homeScreen(CalendarCardService.screenName) !== here) {
                CalendarCardService.posX = -1
                CalendarCardService.posY = -1
                CalendarCardService.screenName = here
            }
            CalendarCardService.setShown(true)
        } else if (id === "palettecard") {
            if (here !== "" && root.homeScreen(PaletteService.screenName) !== here) {
                PaletteService.posX = -1
                PaletteService.posY = -1
                PaletteService.screenName = here
            }
            PaletteService.setShown(true)
        } else if (id === "lyrics") {
            if (here !== "" && root.homeScreen(LyricsService.screenName) !== here) {
                LyricsService.posX = -1
                LyricsService.posY = -1
                LyricsService.screenName = here
            }
            LyricsService.setShown(true)
        } else if (id === "visualizer") {
            if (here !== "" && root.homeScreen(VisualizerService.screenName) !== here) {
                VisualizerService.posX = -1
                VisualizerService.posY = -1
                VisualizerService.bandY = -1
                VisualizerService.bandX = -1
                VisualizerService.screenName = here
            }
            VisualizerService.setShown(true)
        } else if (id === "watertank") {
            if (here !== "" && root.homeScreen(WaterTankService.screenName) !== here) {
                WaterTankService.posX = -1
                WaterTankService.posY = -1
                WaterTankService.screenName = here
            }
            WaterTankService.setShown(true)
        } else if (id === "downloader") {
            if (here !== "" && root.homeScreen(DownloaderService.screenName) !== here) {
                DownloaderService.posX = -1
                DownloaderService.posY = -1
                DownloaderService.screenName = here
            }
            DownloaderService.setShown(true)
        } else if (id === "todo") {
            // One card, on one monitor: adding it on this monitor brings it here (and keeps the choice).
            if (here !== "" && DesktopMonitors.homeFor("todo") !== here) {
                DesktopMonitors.setHome("todo", here)
                TodoService.setPosition(-1, -1, 0)
            }
            TodoService.setShown(true)
        } else if (id === "image") {
            // An empty frame lands on this monitor, at once, and is selected.
            ImageService.setShown(true)
            ImageService.addEmpty(here)
        } else if (id === "notes") {
            // One layer of notes, on one monitor: adding it here brings it here (and keeps the
            // choice); the notes are fitted onto the new screen by the widget.
            if (here !== "" && DesktopMonitors.homeFor("notes") !== here)
                DesktopMonitors.setHome("notes", here)
            // Makes a first note when there is none yet.
            NotesService.setShown(true)
        } else if (PluginService.isPluginId(id)) {
            // A plugin that stays on one monitor: the same as the clock before it had copies.
            const st = PluginService.stateFor(id)
            if (!st)
                return
            if (here !== "" && root.homeScreen(st.screenName) !== here) {
                st.posX = -1
                st.posY = -1
                st.screenName = here
            }
            st.setShown(true)
        }
    }

    function removeWidget(id) {
        if (root.editTarget === id)
            root.editTarget = ""
        if (root.cloneable(id)) {
            root.removeFrom(id, root.screenName)
            return
        }
        if (id === "clock")
            ClockService.setShown(false)
        else if (id === "usercard")
            UserCardService.setShown(false)
        else if (id === "weathercard")
            WeatherCardService.setShown(false)
        else if (id === "calendarcard")
            CalendarCardService.setShown(false)
        else if (id === "palettecard")
            PaletteService.setShown(false)
        else if (id === "lyrics")
            LyricsService.setShown(false)
        else if (id === "todo")
            TodoService.setShown(false)
        else if (id === "notes")
            NotesService.setShown(false)
        else if (id === "visualizer")
            VisualizerService.setShown(false)
        else if (id === "watertank")
            WaterTankService.setShown(false)
        else if (id === "downloader")
            DownloaderService.setShown(false)
        else if (id.indexOf("image:") === 0)
            ImageService.remove(id.slice(6))
        else if (PluginService.isPluginId(id)) {
            const st = PluginService.stateFor(id)
            if (st)
                st.setShown(false)
        }
    }

    // ===== dragging a widget off the shelf =====
    // A slot pulled UP off the shelf (EditTraySlot.qml) follows the pointer as a ghost
    // (EditDragGhost.qml) and is put down where it is let go: on the card, it is added there
    // (or, already on the desktop, moved there), centred on the pointer; back on the shelf or
    // out on the dark stage, nothing happens. Only the monitor the shelf is on: the press that
    // started the drag only knows where the pointer is on that one.
    //   dragId     the widget being dragged ("" = none)
    //   dragX / Y  the pointer, in real pixels from the edited screen's top-left
    //   dragOver   "card" | "shelf" | "" (the dark stage), for the ghost's look
    property string dragId: ""
    property real dragX: 0
    property real dragY: 0
    property string dragOver: ""

    function beginDrag(id) {
        if (!root.active || root.screenName === "")
            return false
        root.dragId = id
        return true
    }

    function moveDrag(x, y, over) {
        root.dragX = x
        root.dragY = y
        root.dragOver = over
    }

    // Ends the drag; `drop` false (Esc, a right click) cancels it.
    function endDrag(drop) {
        const id = root.dragId
        const over = root.dragOver
        root.dragId = ""
        root.dragOver = ""
        if (!drop || id === "" || over !== "card")
            return false
        const scr = Quickshell.screens.find(s => s.name === root.screenName)
        if (!scr)
            return false
        const ui = ShellScale.forScreen(scr)
        const p = SDM.toDesktop(root.dragX, root.dragY, scr.width, scr.height, ui, root.cardRect(scr.width, scr.height, ui))
        if (!p.inside)
            return false
        root.dropWidget(id, p.x, p.y, ui, scr.width / ui, scr.height / ui)
        return true
    }

    // Puts widget `id` on the monitor being edited, centred on (cx, cy) design pixels.
    function dropWidget(id, cx, cy, ui, roomW, roomH) {
        const here = root.screenName
        // The Image tile makes a new empty frame, where it was dropped (ImageService takes real pixels).
        if (id === "image") {
            ImageService.setShown(true)
            ImageService.addEmpty(here, cx * ui, cy * ui)
            return
        }
        const size = root.previewSizes[id] ?? ({ w: 0, h: 0 })
        const at = SDM.spotFor(cx, cy, size.w, size.h, roomW, roomH)
        // On the desktop first (a no-op when it is already here), then on the spot.
        root.addWidget(id)
        if (root.cloneable(id)) {
            if (root.homeOf(id) === here)
                root.svcOf(id).setPosition(at.x, at.y, here, ui)
            else if (WidgetClones.has(id, here))
                WidgetClones.setSpot(id, here, at.x, at.y, ui)
        } else if (id === "todo") {
            TodoService.setPosition(at.x, at.y, ui)
        } else if (id === "visualizer") {
            VisualizerService.setPosition(at.x, at.y, here, ui)
        } else if (id === "watertank") {
            WaterTankService.setPosition(at.x, at.y, here, ui)
        } else if (id === "downloader") {
            DownloaderService.setPosition(at.x, at.y, here, ui)
        } else if (PluginService.isPluginId(id)) {
            const st = PluginService.stateFor(id)
            if (st)
                st.setPosition(at.x, at.y, here, ui)
        }
        // (The Sticky Notes arrange themselves: dropping them just adds them.)
        root.select(id)
        root.ping(id)
    }

    // ===== Lock all =====
    property bool widgetsLocked: true
    property bool lockLoaded: false
    readonly property bool desktopDragAllowed: !root.widgetsLocked && root.screenName === ""

    function setWidgetsLocked(value) {
        root.widgetsLocked = value
        if (root.lockLoaded)
            lockSaver.save(JSON.stringify({ widgetsLocked: root.widgetsLocked }))
    }

    function toggleWidgetsLocked() {
        root.setWidgetsLocked(!root.widgetsLocked)
    }

    readonly property string lockScript: Directories.script("state/edit-state.sh")

    function restoreLock(text) {
        try {
            const s = JSON.parse(text)
            if (typeof s.widgetsLocked === "boolean")
                root.widgetsLocked = s.widgetsLocked
        } catch (e) {
            // No file yet (first run) or an unreadable one: stay locked.
        }
        root.lockLoaded = true
    }

    // Runs once, at startup.
    Process {
        running: true
        command: ["sh", root.lockScript, "load"]
        stdout: StdioCollector {
            onStreamFinished: root.restoreLock(text)
        }
    }

    // Fire-and-forget save that never drops the last state (same as the
    // widgets' services).
    Process {
        id: lockSaver

        property var pending: null

        function save(json) {
            if (lockSaver.running) {
                lockSaver.pending = json
                return
            }
            lockSaver.pending = null
            lockSaver.exec(["sh", root.lockScript, "save", json])
        }

        onExited: {
            if (lockSaver.pending !== null) {
                const json = lockSaver.pending
                lockSaver.pending = null
                lockSaver.exec(["sh", root.lockScript, "save", json])
            }
        }
    }

    // This window's share of the animation: nothing on the other monitors.
    function progressFor(name) {
        return root.editing(name) ? root.progress : 0
    }

    // Where the card ends up (progress = 1) for a screen of w x h real pixels
    // on a monitor scaled by `ui`: the biggest copy of the screen that fits
    // between the shelf and the margins, centred in what is left. The card
    // is the WHOLE screen, bar and dock included (they shrink with the
    // wallpaper: Bar.qml and Dock.qml draw through an EditStage), so nothing
    // is reserved for them.
    function cardRect(w, h, ui) {
        const pad = (root.gap + root.frameWidth) * ui
        let l = pad
        let t = pad
        let r = w - pad
        let b = h - pad
        b -= root.trayHeight * ui
        const vw = Math.max(1, r - l)
        const vh = Math.max(1, b - t)
        const s = Math.max(0.05, Math.min(vw / Math.max(1, w), vh / Math.max(1, h)))
        return { x: l + (vw - w * s) / 2, y: t + (vh - h * s) / 2, s: s }
    }

    // The transform a window applies to its whole content (origin: top-left)
    // right now.
    function scaleFor(name, w, h, ui) {
        const p = root.progressFor(name)
        return 1 + (root.cardRect(w, h, ui).s - 1) * p
    }

    function xFor(name, w, h, ui) {
        return root.cardRect(w, h, ui).x * root.progressFor(name)
    }

    function yFor(name, w, h, ui) {
        return root.cardRect(w, h, ui).y * root.progressFor(name)
    }

    // ===== opening and closing =====
    readonly property bool usingLua: Hyprland.usingLua !== false

    function focusedScreenName() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        for (const s of Quickshell.screens) {
            if (s.name === name)
                return name
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    function openMenu(screen, x, y) {
        // Game Mode takes the widgets away, so there is nothing to edit.
        if (root.active || LockState.locked || GameModeService.enabled)
            return
        root.menuScreen = screen
        root.menuX = x
        root.menuY = y
        root.menuOpen = true
    }

    function closeMenu() {
        root.menuOpen = false
    }

    // ===== not on a workspace with applications =====
    // Edit Desktop is for the desktop itself, so it does not start while an application is on
    // the monitor's active workspace (go to an empty one first). A window that is pinned, hidden
    // or not mapped (a minimised one) does not count. Read from Quickshell's own Hyprland
    // models, so the answer is there at once and nothing is spawned.
    function appsOn(name) {
        const m = Hyprland.monitors.values.find(x => x.name === name)
        const ws = m && m.activeWorkspace ? m.activeWorkspace.id : 0
        if (ws <= 0)
            return false
        const tl = Hyprland.toplevels.values
        for (let i = 0; i < tl.length; i++) {
            const o = tl[i].lastIpcObject || {}
            if (!tl[i].workspace || tl[i].workspace.id !== ws)
                continue
            if (o.mapped === false || o.hidden === true || o.pinned === true)
                continue
            return true
        }
        return false
    }

    // One short notice, not one per key press.
    property double lastRefusal: 0

    function refuse() {
        const now = Date.now()
        if (now - root.lastRefusal < 2500)
            return
        root.lastRefusal = now
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "material:edit_off",
            "Edit Desktop", "Go to an empty workspace to edit the desktop."])
    }

    function open(screen, tab) {
        if (LockState.locked || GameModeService.enabled)
            return
        const name = (typeof screen === "string" && screen !== "") ? screen : root.focusedScreenName()
        if (name === "")
            return
        // Already open there: nothing to do. Open on another monitor (one you may not even be
        // looking at): it moves here, so asking for Edit Desktop always brings it to you.
        if (root.active && root.screenName === name)
            return
        if (root.appsOn(name)) {
            root.refuse()
            return
        }
        if (root.active) {
            root.active = false
            root.editTarget = ""
            root.endDrag(false)
            root.unpark()
        }
        root.requestedTab = (typeof tab === "string" && tab !== "") ? tab : "widgets"
        root.menuOpen = false
        root.editTarget = ""
        root.sharedScreens = root.otherScreens(name)
        root.screenName = name
        root.active = true
        root.park(name)
        exitAnim.stop()
        enterAnim.restart()
    }

    function close() {
        if (!root.active)
            return
        root.active = false
        root.editTarget = ""
        root.endDrag(false)
        root.unpark()
        enterAnim.stop()
        exitAnim.restart()
    }

    // Open or close on the monitor you are using: open on another one, it moves here.
    function toggle() {
        if (root.active && root.screenName === root.focusedScreenName())
            root.close()
        else
            root.open("")
    }

    // The way in is a pop (it overshoots the card a touch and settles, like
    // the Quick Panel coming out of a pocket); the way out is a plain ease.
    NumberAnimation {
        id: enterAnim
        target: root
        property: "progress"
        to: 1
        duration: 560
        easing.type: Easing.OutBack
        easing.overshoot: 1.25
    }

    NumberAnimation {
        id: exitAnim
        target: root
        property: "progress"
        to: 0
        duration: 360
        easing.type: Easing.InOutCubic
        onFinished: {
            if (!root.active) {
                root.screenName = ""
                root.sharedScreens = []
            }
        }
    }

    // ===== getting the windows out of the way =====
    property int savedWorkspace: 0
    property string savedMonitor: ""
    property string toggledSpecial: ""

    function dispatch(lua, classic) {
        Hyprland.dispatch(root.usingLua ? lua : classic)
    }

    function park(name) {
        root.savedWorkspace = 0
        root.savedMonitor = ""
        root.toggledSpecial = ""
        root.holdWorkspace = 0
        settle.stop()
        probe.running = true
    }

    // `hyprctl -j clients` and `-j monitors` in one JSON document.
    Process {
        id: probe
        command: ["sh", "-c", "printf '{\"c\":'; hyprctl -j clients; printf ',\"m\":'; hyprctl -j monitors; printf '}'"]
        stdout: StdioCollector {
            onStreamFinished: root.parkFrom(text)
        }
    }

    function parkFrom(text) {
        // Closed again before the answer came back.
        if (!root.active || root.screenName === "")
            return
        try {
            const d = JSON.parse(text)
            const name = root.screenName
            const m = (d.m || []).find(x => x.name === name)
            if (!m)
                return
            const ws = m.activeWorkspace ? m.activeWorkspace.id : 0

            // A special workspace (a scratchpad) shown over the desktop is
            // closed first, the same way the lock does it.
            const sp = m.specialWorkspace
            if (sp && sp.id !== 0 && typeof sp.name === "string" && sp.name !== "") {
                const clean = sp.name.startsWith("special:") ? sp.name.substring(8) : sp.name
                root.toggledSpecial = clean
                root.dispatch("hl.dsp.focus({ monitor = \"" + name + "\" })", "focusmonitor " + name)
                root.dispatch("hl.dsp.workspace.toggle_special('" + clean + "')", "togglespecialworkspace " + clean)
            }

            if (!ws || ws < 0)
                return
            const busy = (d.c || []).some(w => w.workspace && w.workspace.id === ws && !w.pinned && w.mapped !== false)
            if (!busy) {
                root.holdWorkspace = ws
                return
            }
            settle.restart()
            root.savedWorkspace = ws
            root.savedMonitor = name
            root.dispatch("hl.dsp.focus({ monitor = \"" + name + "\" })", "focusmonitor " + name)
            root.dispatch("hl.dsp.focus({ workspace = 'empty' })", "workspace empty")
        } catch (e) {
            console.log("EditMode: could not read hyprctl output: " + e)
        }
    }

    function unpark() {
        settle.stop()
        root.holdWorkspace = 0
        const ws = root.savedWorkspace
        const name = root.savedMonitor
        const sp = root.toggledSpecial
        root.savedWorkspace = 0
        root.savedMonitor = ""
        root.toggledSpecial = ""
        if (ws > 0 && name !== "") {
            root.dispatch("hl.dsp.focus({ monitor = \"" + name + "\" })", "focusmonitor " + name)
            root.dispatch("hl.dsp.focus({ workspace = " + ws + " })", "workspace " + ws)
        }
        if (sp !== "")
            root.dispatch("hl.dsp.workspace.toggle_special('" + sp + "')", "togglespecialworkspace " + sp)
    }

    // ===== keeping the workspace where it is =====
    property int holdWorkspace: 0

    function holdNow() {
        if (!root.active || root.screenName === "")
            return
        const m = Hyprland.monitors.values.find(x => x.name === root.screenName)
        const id = m && m.activeWorkspace ? m.activeWorkspace.id : 0
        root.holdWorkspace = id > 0 ? id : 0
    }

    // The 'empty workspace' jump (see park) lands a moment after it is sent;
    // read where we ended up once it has settled.
    Timer {
        id: settle
        interval: 350
        onTriggered: root.holdNow()
    }

    function onHyprlandEvent(event) {
        if (!root.active || root.holdWorkspace <= 0)
            return
        const mon = Hyprland.focusedMonitor
        if (event.name === "workspacev2") {
            // data: "<id>,<name>". Only the monitor being edited matters.
            if (!mon || mon.name !== root.screenName)
                return
            const id = parseInt(event.data.split(",")[0])
            if (isNaN(id) || id === root.holdWorkspace)
                return
            root.dispatch("hl.dsp.focus({ workspace = " + root.holdWorkspace + " })",
                          "workspace " + root.holdWorkspace)
        } else if (event.name === "activespecialv2") {
            // data: "<id>,<name>,<monitor>". An empty name means it was closed.
            const parts = event.data.split(",")
            if (parts.length < 3 || parts[2] !== root.screenName)
                return
            const full = parts[1]
            if (full === "")
                return
            const clean = full.startsWith("special:") ? full.substring(8) : full
            root.dispatch("hl.dsp.workspace.toggle_special('" + clean + "')",
                          "togglespecialworkspace " + clean)
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.onHyprlandEvent(event)
        }
    }

    // Whether the desktop widgets (clock, To-Do, user card, weather card, visualizer; not the notes, which are always full-screen) may shrink their
    // window to a box around the card while nothing is being edited. Off by default: the
    // switch between that small window and the full-screen one Edit Desktop needs made
    // every widget jump a little when Done was pressed (confirmed: the jump is gone
    // with full-screen windows). On saves the compositor blending a full-screen layer
    // for every frame a widget draws, but brings the jump back.
    //   qs -c sekaipop ipc call desktopedit compactwindows true   (until the next reload)
    // Low-end mode (Settings -> Desktop -> Low-end mode, `perf.lowEnd`) turns it on and stays on
    // until the switch is turned off; the ipc call overrides both until the next reload.
    property var compactOverride: undefined
    readonly property bool compactWindows: root.compactOverride !== undefined
        ? !!root.compactOverride : SettingsService.flag("perf.lowEnd")

    // ===== ipc =====
    IpcHandler {
        target: "desktopedit"

        function compactwindows(on: bool): void {
            root.compactOverride = on;
        }

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open("");
        }

        // Edit Desktop on its THEME tab (what `theme toggle` does too).
        function theme(): void {
            ThemeService.togglePicker();
        }

        // ...with the Matugen theme on and its controls up (scheme, seed, contrast, pins).
        function matugen(): void {
            root.openMatugen();
        }

        function close(): void {
            root.close();
        }

        // While editing, put the shelf on another monitor (every monitor is being edited, the
        // shelf is only on the main one):  qs -c sekaipop ipc call desktopedit main DP-2
        function main(screen: string): string {
            return root.setMain(screen) ? "main monitor is " + screen : "nothing changed";
        }

        // Move a widget from the monitor being edited (or the focused one) to another monitor:
        //   qs -c sekaipop ipc call desktopedit movewidget lyrics DP-2
        // ids: clock, usercard, weathercard, calendarcard, palettecard, lyrics, plugin:<id>
        function movewidget(id: string, screen: string): string {
            return root.moveWidget(id, screen) ? "moved " + id + " to " + screen : "nothing moved";
        }

    }
}
