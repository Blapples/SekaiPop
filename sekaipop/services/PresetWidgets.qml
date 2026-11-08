pragma Singleton
import QtQuick
import Quickshell

// Every desktop widget a preset knows about. DesktopPresetService saves, wears and
// compares the widgets by walking this list, so a new widget is ONE entry here, not
// edits in five places.
//
// The rule (modules/common/functions/PresetParts.js, unit-tested):
//   a preset wears what it holds;
//   anything it can't hold, because it was saved BEFORE that existed, is worn as the way
//   things were back then, so wearing an old preset gives the same result whatever the
//   widget is set to now:
//     - a widget it has no part for is switched OFF,
//     - a style / size / direction it has no value for is worn as the entry's `before`.
//   The first is automatic for every entry below. The second is ONE LINE per new option.
//
// ===== Adding a desktop widget =====
//   1. Give its service what the other widgets' services have:
//        property bool loaded / property bool shown
//        function setShown(value)             (the thing an old preset calls with false)
//        function snapshot() / restore(text) / persist()
//      snapshot() is what the preset holds, so leave out anything that is the user's
//      own (a to-do's tasks, a calendar's events) or the machine's, or name it in `skip`.
//   2. Add an entry to `list` below (copy the closest one).
//        { id: "mywidget", service: MyWidgetService, skip: ["events"] }
//      The id is the key inside a preset's `widgets`; keep it the same as the widget's
//      `widgetId` in shell.qml and its id in EditMode.widgetList.
//      Settings Panel keys the widget has (say `mywidget.*`) travel in a preset's `settings`
//      on their own, and an older preset puts them back to their defaults. If some are the
//      user's own and must survive wearing a preset, add them to keepExact / keepPrefix in
//      DesktopPresetService.qml.
//   3. Later, when you ADD an option to a widget (a new style, a new size, a new
//      direction), add it to the entry's `before` with what the widget was before the
//      option existed:
//        before: { style: "classic" }
//      Without that line an old preset would leave the new option as it is now.
//   4. Run `node tests/preset-widgets-test/registry_unit.js`. It fails when a widget in
//      shell.qml has no entry, or an entry's service lacks something above.
//   That is all. Nothing else needs to know about it: saving, wearing, the "you are
//   wearing this one" tick and old presets all follow from the entry.
//
// Only if the widget is NOT "snapshot() out, restore() back in" (it keeps something
// the preset must handle differently, like the To-Do's spot or the image frames' files)
// give the entry its own `capture` and `wear`; see todo / notes / images below.
//
// Optional polish, not needed for presets to work: PresetMotion.qml has a shrink-away
// flag per widget (clockOut, todoOut ...) that DesktopPresetService.motionPlan() fills.
// A widget without one just uses its normal show / hide animation when a preset
// changes it.
//
// ORDER matters a little: widgets are worn top to bottom.
Singleton {
    id: root

    readonly property var list: [
        { id: "clock", service: ClockService, skip: ["use24h"] },

        // A preset saved before the 1x1 size existed has the card as it always was: "2x2".
        { id: "usercard", service: UserCardService, before: { size: "2x2" } },

        // The style is "classic" or "minimal". A preset saved before Minimal existed has no
        // style and wears classic. ("full" was classic's old name: a preset that says it
        // means classic.) A preset saved before the 1x1 size existed wears 2x2.
        {
            id: "weathercard",
            service: WeatherCardService,
            before: { style: "classic", size: "2x2" },
            normalize: part => part.style === "full" ? Object.assign({}, part, { style: "classic" }) : part
        },

        // The visualizer's audio engine and performance switches are the machine's.
        // An older preset has no `vertical` / `bandX`: it means a band along the bottom.
        {
            id: "visualizer",
            service: VisualizerService,
            skip: ["alwaysListen", "analyzer", "useAubio", "perf", "stayWhenPaused"],
            before: { vertical: false, bandX: -1 }
        },

        // Position, size and on / off: the tasks are yours, not the look's. A preset saved
        // before the size was part of one has the card as it always was: "full".
        {
            id: "todo",
            service: TodoService,
            capture: () => ({
                x: TodoService.posX,
                y: TodoService.posY,
                scale: TodoService.posScale,
                shown: TodoService.shown,
                size: TodoService.size
            }),
            wear: part => {
                if (typeof part.x === "number" && typeof part.y === "number")
                    TodoService.setPosition(part.x, part.y, part.scale)
                TodoService.setShown(part.shown !== false)
                if (part.size === "2x2" || part.size === "full")
                    TodoService.setSize(part.size)
            },
            before: { size: "full" }
        },

        // Only the look (place, size, on / off): the events are yours. A preset saved before
        // the size existed has the card as it always was: "full".
        { id: "calendarcard", service: CalendarCardService, skip: ["events"], before: { size: "full" } },

        // Only the look: the palette's colours, locks and favourites are yours. A preset saved
        // before the size existed has the card as it always was: "full".
        {
            id: "palettecard",
            service: PaletteService,
            skip: ["v", "colors", "locks", "source", "scheme", "favorites", "prev", "fresh"],
            before: { size: "full" }
        },

        // Only the look (place, size, on / off): the glasses you have had, the goal, the size of a glass
        // and the last days are yours, not the look's.
        { id: "watertank", service: WaterTankService, skip: ["goal", "glassMl", "glasses", "day", "history"] },

        // Only the look (place, size, on / off): the options, the cobalt address and key, the browser
        // login and the finished downloads are yours, not the look's.
        {
            id: "downloader",
            service: DownloaderService,
            skip: ["engine", "mode", "quality", "audioFormat", "folder", "cobaltUrl", "cobaltKey", "notify", "cookies", "cookiesFile", "subs", "names", "askWhich", "done"]
        },

        // Only the look (place, on / off, and the whole-screen kinetic look with its style, colors and dim):
        // the sync nudges belong to your player and your songs, not to a look. A preset saved before
        // the kinetic look existed has the card as it always was: kinetic off, the dim and colors at
        // their defaults (and the poster style).
        {
            id: "lyrics",
            service: LyricsService,
            skip: ["syncMs", "offsets"],
            before: { kinetic: false, kineticDim: 0.45, kineticColors: "theme", kineticCamera: "drift", kineticStyle: "poster" }
        },

        // The sticky notes: on / off here. Their content is per preset but kept by NotesService
        // itself (switchSet / adoptSet / renameSet / dropSet, called by DesktopPresetService).
        {
            id: "notes",
            service: NotesService,
            capture: () => ({ shown: NotesService.shown }),
            wear: part => NotesService.setShown(part.shown !== false)
        },

        // The custom pictures: on / off AND every frame. The pictures' files are copied
        // beside the preset by DesktopPresetService (ctx.wearFrames). A preset saved
        // before frames were part of one holds on / off only and leaves your frames alone,
        // and is compared on on / off only.
        {
            id: "images",
            service: ImageService,
            capture: () => DesktopPresetService.imagesPart(),
            wear: (part, ctx) => {
                ImageService.setShown(part.shown !== false)
                if (Array.isArray(part.items))
                    ctx.wearFrames(part.items)
            },
            digestStub: () => ({})
        }
    ]

    // What DesktopPresetService walks: the widgets above, then the desktop widget plugins
    // (services/PluginService.qml), one entry each, made there: `{ id: "plugin:<id>",
    // service: <its PluginState>, skip: ["settings"] }`. A preset holds a plugin's on / off
    // and spot, and the one rule above holds for it too: a preset saved before the plugin
    // was installed switches it off. Keep `list` a plain literal: the tests read it as text.
    readonly property var all: root.list.concat(PluginService.presetEntries)
}
