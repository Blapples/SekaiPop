import QtQuick
import Quickshell
import Quickshell.Wayland
import "../bar/CalendarMath.js" as CM
import "../../common/functions/EventMath.js" as EM
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The desktop calendar card: a month, today, and what is coming up, as a stack of
// event cards. It sits on the desktop under your windows, over the wallpaper, with
// the same drag, lock, scale, monitors, Edit Desktop and Focus Mode as the weather
// card and the clock.
//
//   The plate      (SekaiPlate, the header the bar popups share) the month as a
//                  sticker, the year (and this week's number) above it, and today as
//                  a tilted dark disc: click it and the card turns back to today. The
//                  month's tally hangs off the plate's lower edge on a slanted tab
//                  ("4 events, 2 due"; coral when a deadline has passed), with the
//                  two page keys beside it. The wheel over the days pages too.
//   The days       keycaps, like the bar's calendar. Today is the raised gradient
//                  key. A day that has entries is washed with the colour of its first
//                  one and wears up to three diamonds (one per colour); a day with an
//                  open deadline gets a flag in the corner (coral when it is late or
//                  due today, amber within three days, grey further out). Click a day
//                  to see just its entries, click it again to go back; double-click a
//                  day to add something to it; a faded day from the next or last month
//                  turns the page. The row under the pointer is read out on the plate.
//   The cards      "Coming up": every open deadline that has passed (they stay until
//                  you tick them off), then everything from today on. Each is a
//                  Project SEKAI style banner: a slanted block in the entry's colour
//                  with its day, the title, the time and note, and a chip that counts
//                  down ("in 3 days", "Due tomorrow", "2 days late", "Done"). Click a
//                  card to open it: the full date, the whole note, and the buttons —
//                  Done / Undo (deadlines), Edit, Delete.
//   The form       the "+" key (or a double-click on a day) swaps the list for a form:
//                  title, note, time (24 h, "9:30" or "0930" work; empty = all day),
//                  Event or Deadline, and one of the five attribute colours. The day
//                  is the one selected in the grid: click another day to move it.
//                  Enter saves, Esc cancels.
//
// The events are yours and live in services/CalendarCardService.qml (remembered
// across restarts, nothing expires). All the rules are in
// modules/common/functions/EventMath.js. The card is OFF until you add it (Edit
// Desktop's shelf, Settings -> Desktop, or the ipc), and a desktop preset does not
// carry it.
//
// How the moving works: exactly like WeatherCardWidget.qml. ONE transparent window with
// the card as an Item inside it. Dragging just moves that Item, so it stays smooth, and
// the window's input `mask` is only the card, so every click anywhere else passes
// straight through to whatever is underneath. Keyboard focus is OnDemand (you can type
// into the form; clicking a real window hands the keyboard back).
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call calendarcard toggle          (show / hide)
//   qs -c sekaipop ipc call calendarcard add "Rehearsal" 2026-10-23 14:00 event
//                                                       (title, day, time or "", event | deadline)
//   qs -c sekaipop ipc call calendarcard resetPosition   (if it ever ends up off-screen)

PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    function resetPosition(): void {
        win.clearSpot();
        win.place();
        win.saveSpot(card.x, card.y);
    }
    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor the card was last dropped on (remembered in
    // CalendarCardService), or the first screen if it has never been moved.
    property string monitor: ""

    // A copy on another monitor (WidgetClones.qml): the same widget, with a spot of its own. The main
    // copy keeps its spot in the service as before.
    property bool clone: false

    readonly property var cloneSpot: win.clone ? WidgetClones.spot("calendarcard", win.wantedScreen) : null
    readonly property bool spotReady: win.clone ? (WidgetClones.loaded && win.cloneSpot !== null) : CalendarCardService.loaded
    readonly property real spotX: win.clone ? (win.cloneSpot ? win.cloneSpot.x : -1) : CalendarCardService.posX
    readonly property real spotY: win.clone ? (win.cloneSpot ? win.cloneSpot.y : -1) : CalendarCardService.posY
    readonly property real spotScale: win.clone ? (win.cloneSpot ? win.cloneSpot.scale : 0) : CalendarCardService.posScale

    function saveSpot(x, y): void {
        if (win.clone)
            WidgetClones.setSpot("calendarcard", win.wantedScreen, x, y, win.uiScale)
        else
            CalendarCardService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        if (win.clone) {
            WidgetClones.clearSpot("calendarcard", win.wantedScreen)
        } else {
            CalendarCardService.posX = -1
            CalendarCardService.posY = -1
        }
    }

    function fixSpotScale(): void {
        if (win.clone) {
            WidgetClones.setSpot("calendarcard", win.wantedScreen, win.spotX, win.spotY, win.uiScale)
        } else {
            CalendarCardService.posScale = win.uiScale
            CalendarCardService.persist()
        }
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : CalendarCardService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card is
    // drawn in design pixels inside a ScaleHost, so `roomW` x `roomH` is the
    // screen as the card sees it (real size / scale); positions are kept in
    // that same design space.
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real fullW: win.screen ? win.screen.width : 0
    readonly property real fullH: win.screen ? win.screen.height : 0
    readonly property real roomW: win.fullW / win.uiScale
    readonly property real roomH: win.fullH / win.uiScale

    // ===== a small window while nothing needs the whole screen =====
    // See WeatherCardWidget.qml: at rest the window is just the card plus some room
    // around it, and only Edit Desktop (and dragging on an unlocked desktop) gets the
    // full screen back. Everything inside still lives in screen coordinates: `shifter`
    // slides the whole stage by the window's own position.
    readonly property bool compact: !EditMode.active && !win.gliding && EditMode.screenName === ""
        && EditMode.compactWindows && !EditMode.desktopDragAllowed && win.fullW > 0 && win.placed
    readonly property real boxPad: Math.ceil((0.16 * Math.max(card.width, card.height) + 24) * win.uiScale)
    readonly property real boxX: win.compact ? Math.max(0, Math.floor(card.x * win.uiScale - win.boxPad)) : 0
    readonly property real boxY: win.compact ? Math.max(0, Math.floor(card.y * win.uiScale - win.boxPad)) : 0
    readonly property real boxW: Math.max(1, Math.min(win.fullW,
        Math.ceil((card.x + card.width) * win.uiScale + win.boxPad)) - win.boxX)
    readonly property real boxH: Math.max(1, Math.min(win.fullH,
        Math.ceil((card.y + card.height) * win.uiScale + win.boxPad)) - win.boxY)

    // On / off: the card pops in with a little overshoot and is swallowed (straight
    // shrink) on the way out; the window stays up until the swallow has finished.
    // Two fixed animations, started from onWantChanged (see WeatherCardWidget.qml).
    //
    // Desktop Focus Mode (FocusGate.qml): `gate.show` is false while an application is
    // on this monitor's workspace, so `want` goes false and the swallow + unmap hide it.
    FocusGate {
        id: gate
        widgetId: "calendarcard"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: CalendarCardService.shown && CalendarCardService.loaded
    readonly property bool want: win.switchedOn && gate.show
    property real reveal: 0

    // Off while the saved state is read back, so a reload doesn't replay the pop.
    property bool armed: false

    // Stays false until the card has been put on its saved spot, and keeps it drawn at
    // size 0 until then (after a reload the window maps before the compositor has told
    // it its real size).
    property bool placed: false

    onWantChanged: {
        if (!win.armed) {
            popIn.stop()
            swallow.stop()
            win.reveal = win.want ? 1 : 0
        } else if (win.want) {
            swallow.stop()
            popIn.restart()
        } else {
            popIn.stop()
            swallow.restart()
        }
    }

    NumberAnimation {
        id: popIn
        target: win
        property: "reveal"
        to: 1
        duration: 460
        easing.type: Easing.OutBack
        easing.overshoot: 1.9
    }

    NumberAnimation {
        id: swallow
        target: win
        property: "reveal"
        to: 0
        duration: 300
        easing.type: Easing.InCubic
    }

    Timer {
        interval: 800
        running: CalendarCardService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // On screen, or switched on and not suspended by Focus Mode.
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a transparent layer that is only sitting there
    // still costs the compositor a blend on every frame.
    visible: CalendarCardService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock (see WeatherCardWidget.qml), up a layer while edited / moved.
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-calendarcard"
    // Not while editing: the shelf keeps the keyboard then (Esc), and a click on a card must
    // not take it away. The exception is this card while it is selected for editing: then it
    // is used like on the desktop, so it can take the keyboard to type an event.
    WlrLayershell.keyboardFocus: (EditMode.active && EditMode.editTarget !== "calendarcard") || !keys.wanted
        ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        left: true
        right: !win.compact
        bottom: !win.compact
    }

    margins {
        left: win.boxX
        top: win.boxY
    }

    implicitWidth: win.boxW
    implicitHeight: win.boxH

    // Only the card takes clicks; the rest of the screen falls through.
    mask: Region {
        item: cardMask
    }

    // Edit Desktop widens the card's rectangle a little (its outline and tag sit half
    // outside it); `stage` is the transform the content is drawn with.
    Item {
        id: cardMask
        readonly property real m: stage.editing ? 38 : 0
        readonly property real k: win.uiScale * stage.scale
        readonly property real x1: shifter.x + stage.x + (card.x + card.width + m) * k
        readonly property real y1: shifter.y + stage.y + (card.y + card.height + m) * k
        x: !win.live ? 0 : Math.max(0, Math.round(shifter.x + stage.x + (card.x - m) * k))
        y: !win.live ? 0 : Math.max(0, Math.round(shifter.y + stage.y + (card.y - m) * k))
        width: !win.live ? 1 : Math.max(0, Math.ceil(x1) - x)
        height: !win.live ? 1 : Math.max(0, Math.ceil(y1) - y)
    }

    // ===== the date =====
    // "Now", ticking every minute, so today rolls over at midnight without another timer.
    SystemClock {
        id: clock
        enabled: win.working || EditMode.active
        precision: SystemClock.Minutes
    }

    readonly property date today: clock.date
    // Qt: Monday = 1 ... Sunday = 7; CalendarMath wants Sunday = 0, Monday = 1.
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7

    // 0 = the current month; the keys / wheel / disc move it.
    property int monthShift: 0
    readonly property date viewDate: CM.monthStart(win.today, win.monthShift)
    readonly property int viewYear: win.viewDate.getFullYear()
    readonly property int viewMonth: win.viewDate.getMonth()
    readonly property var cells: CM.monthGrid(win.viewDate, win.today, win.firstDay)
    readonly property var weekdays: CM.weekdayLabels(win.firstDay)
    readonly property string todayKey: EM.keyOf(win.today)

    // ===== the events =====
    readonly property var events: CalendarCardService.events
    readonly property var byDay: CalendarCardService.byDay
    readonly property var summary: EM.monthSummary(win.events, win.viewYear, win.viewMonth, win.today)
    readonly property var comingUp: EM.upcoming(win.events, win.today, 80)

    // The day whose entries the list shows ("" = "Coming up"). While the form is open it is
    // the day the entry goes on.
    property string selectedKey: ""
    readonly property var dayEntries: win.selectedKey !== "" ? (win.byDay[win.selectedKey] || []) : []
    readonly property var shownList: win.selectedKey !== "" ? win.dayEntries : win.comingUp
    readonly property int selectedDiff: win.selectedKey !== "" ? EM.diffTo(win.today, win.selectedKey) : 0

    // The entry that is open (its buttons showing).
    property string expandedId: ""

    // The form.
    property bool forming: false
    property string formId: ""
    property string formKind: "event"
    property int formColor: 0
    readonly property var formTime: EM.normalizeTime(timeField.text)
    readonly property bool formValid: titleField.text.trim() !== "" && win.formTime !== null

    // What the pointer is on.
    property int hoverIndex: -1
    readonly property var hoverCell: win.hoverIndex >= 0 && win.hoverIndex < win.cells.length ? win.cells[win.hoverIndex] : null

    // Weekends, late deadlines and near ones (the bar calendar's coral on the dark looks).
    readonly property color weekendInk: mt.dark ? "#ff8fa3" : "#e0575b"
    readonly property color alertInk: win.weekendInk
    readonly property color alertText: mt.dark ? mt.colBorder : "#ffffff"
    readonly property color soonInk: mt.dark ? "#ffc266" : "#f0a030"

    function attr(i) {
        return Qt.color(mt.attributeColors[Math.max(0, Math.min(mt.attributeColors.length - 1, i))])
    }

    // `base` with `c` washed over it at `a` (0..1).
    function wash(base, c, a) {
        return Qt.tint(base, Qt.rgba(c.r, c.g, c.b, a))
    }

    // The ink a deadline state is drawn in.
    function stateInk(st) {
        if (st === "overdue" || st === "today")
            return win.alertInk
        if (st === "soon")
            return win.soonInk
        return mt.pInkSub
    }

    // ===== paging and selecting =====
    property real gridWave: 1
    readonly property real gridWaveMs: 800

    NumberAnimation {
        id: gridWaveAnim
        target: win
        property: "gridWave"
        from: 0
        to: 1
        duration: win.gridWaveMs
    }

    onMonthShiftChanged: {
        win.hoverIndex = -1
        if (win.armed)
            gridWaveAnim.restart()
    }

    function page(by) {
        win.monthShift = win.monthShift + by
    }

    function goToday() {
        win.monthShift = 0
        if (!win.forming)
            win.selectedKey = ""
        else
            win.selectedKey = win.todayKey
    }

    // Shows the month a day belongs to (a faded day of the next / last month).
    function showMonthOf(cell) {
        if (!cell.inMonth)
            win.monthShift = CM.shiftFor(win.today, cell.y, cell.m)
    }

    function clickDay(cell) {
        if (win.forming) {
            win.selectedKey = cell.key
        } else {
            win.selectedKey = win.selectedKey === cell.key ? "" : cell.key
            win.expandedId = ""
        }
        win.showMonthOf(cell)
    }

    // ===== the form =====
    function openForm(id, key) {
        const e = id !== "" ? CalendarCardService.find(id) : null
        if (!e && CalendarCardService.full)
            return
        win.formId = e ? e.id : ""
        win.formKind = e ? e.kind : "event"
        win.formColor = e ? e.color : (win.events.length % 5)
        titleField.text = e ? e.title : ""
        noteField.text = e ? e.note : ""
        timeField.text = e ? e.time : ""
        win.selectedKey = e ? e.date : (key !== "" ? key : win.todayKey)
        const p = EM.parseDate(win.selectedKey)
        if (p)
            win.monthShift = CM.shiftFor(win.today, p.y, p.m)
        win.forming = true
        Qt.callLater(() => titleField.input.forceActiveFocus())
    }

    function closeForm() {
        win.forming = false
        win.formId = ""
        titleField.text = ""
        noteField.text = ""
        timeField.text = ""
        card.forceActiveFocus()
    }

    function saveForm() {
        if (!win.formValid)
            return
        const fields = {
            title: titleField.text,
            date: win.selectedKey,
            time: win.formTime,
            note: noteField.text,
            color: win.formColor,
            kind: win.formKind
        }
        list.keepY = list.contentY
        if (win.formId === "") {
            const id = CalendarCardService.add(fields)
            if (id === "")
                return
            win.expandedId = id
        } else if (!CalendarCardService.update(win.formId, fields)) {
            return
        }
        win.closeForm()
    }

    function toggleDone(e) {
        list.keepY = list.contentY
        CalendarCardService.setDone(e.id, !e.done)
    }

    function deleteEvent(e) {
        list.keepY = list.contentY
        if (win.expandedId === e.id)
            win.expandedId = ""
        CalendarCardService.remove(e.id)
    }

    // Called by the ipc (shell.qml): an entry from a script.
    function addEntry(title, date, time, kind): bool {
        return CalendarCardService.add({ title: title, date: date, time: time, kind: kind }) !== ""
    }

    Gradient {
        id: accentGradient
        GradientStop { position: 0.0; color: mt.accentMint }
        GradientStop { position: 1.0; color: mt.accentCyan }
    }

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is
        // still smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!CalendarCardService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        let x = win.spotX
        let y = win.spotY
        if (x < 0 || y < 0) {
            // The first spot: up on the right, clear of the bar.
            x = win.roomW - card.width - 48
            y = 72
        } else if (win.spotScale > 0 && win.uiScale > 0) {
            // Saved at another shell scale: same spot on the screen, not the same
            // design pixels (the card keeps its top-left corner).
            const k = win.spotScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    // After a reload the window, the monitor list and scale.json all settle over a few
    // frames; place again once they have, so the card always ends on its saved spot
    // (never while it is being dragged).
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            if (win.spotReady && win.spotX >= 0 && win.spotScale <= 0 && !dragArea.drag.active)
                win.fixSpotScale()
            if (!chrome.dragging && !dragArea.drag.active)
                win.place(!win.placed && CalendarCardService.loaded)
        }
    }

    // place() runs one turn of the event loop later (Qt.callLater), not inside the window's own
    // size change: the size is boxW / boxH, which read card.x / card.y, which place() sets
    // (Qt logged "Binding loop detected for property implicitWidth"). Same as ClockWidget.qml.
    // To undo: `onWidthChanged: { win.place(); settle.restart() }` (same for the height).
    onWidthChanged: { Qt.callLater(win.place); settle.restart() }
    onHeightChanged: { Qt.callLater(win.place); settle.restart() }
    onUiScaleChanged: { win.place(); settle.restart() }
    onScreenChanged: { win.place(); settle.restart() }
    onVisibleChanged: settle.restart()
    Component.onCompleted: {
        win.reveal = win.want ? 1 : 0
        win.place()
    }

    // The spot of a copy changed (a drag, a reset): put the card there.
    Connections {
        target: WidgetClones
        enabled: win.clone
        function onSpotsChanged() { follow.restart() }
    }

    Connections {
        target: CalendarCardService
        function onLoadedChanged() {
            win.place()
            settle.restart()
        }
        // Something else (Edit Desktop moving the card to this monitor) hands the
        // service another spot while the card is on screen. The spot arrives as
        // several properties one after the other, so wait a beat and place once.
        function onPosXChanged() { follow.restart() }
        function onPosYChanged() { follow.restart() }
        function onPosScaleChanged() { follow.restart() }
    }

    // The card glides to its new spot instead of jumping (not while it is being dragged,
    // and not when it is already where it should be). `gliding` first, so a small window
    // grows to the whole screen (see `compact`), then `glideOn` switches the Behaviors on.
    property bool gliding: false
    property bool glideOn: false

    Timer {
        id: follow
        interval: 16
        onTriggered: {
            if (chrome.dragging || dragArea.drag.active)
                return
            const ox = card.x
            const oy = card.y
            win.place()
            if (Math.abs(card.x - ox) + Math.abs(card.y - oy) < 2)
                return
            card.x = ox
            card.y = oy
            win.gliding = true
            glideStart.restart()
        }
    }

    Timer {
        id: glideStart
        interval: 80
        onTriggered: {
            win.glideOn = true
            win.place()
            glideEnd.restart()
        }
    }

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
        }
    }

    // Edit Desktop's shelf shows the card as it really looks: a picture of it, taken
    // every second while the mode is on (EditPreview.qml).
    EditPreview {
        widgetId: win.clone ? "" : "calendarcard"
        target: card
        pixelRatio: win.uiScale
    }

    // ===== Edit Desktop =====
    Item {
        id: shifter
        x: -win.boxX
        y: -win.boxY
        width: win.fullW
        height: win.fullH

    // Edit Desktop shrinks every desktop window into the same card with the same
    // transform (see EditStage.qml / services/EditMode.qml). Out of edit mode this is a
    // no-op: scale 1, no offset.
    EditStage {
        id: stage
        screenObj: win.screen
        uiScale: win.uiScale

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Item {
                id: card

                // Gliding to a new spot (win.glideOn, see `follow`). Off the rest of the
                // time, so dragging and placing are exact.
                Behavior on x {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }
                Behavior on y {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }

                // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
                readonly property bool classicPanel: true

                // The content is as tall as its parts (below); the housing adds the inset on
                // every side plus the hard shadow underneath.
                // The 2 x 2 size (CalendarCardService.size) is the footprint the clock, user card
                // and weather card share: 286 x 238 of content, 320 x 276 with the housing.
                readonly property bool small: CalendarCardService.small
                // The 1 x 1 size is a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with
                // the housing. It shows only today's day and date (CalendarTile.qml).
                readonly property bool tiny: CalendarCardService.tiny
                readonly property int contentW: card.tiny ? 120 : (card.small ? 286 : 312)
                readonly property int contentH: card.tiny ? 94 : (card.small ? 238 : col.implicitHeight)
                readonly property int inset: mt.borderWidth + mt.outerRingWidth + 10

                width: card.contentW + card.inset * 2
                height: card.contentH + card.inset * 2 + mt.shadowOffset

                scale: Math.max(0, win.reveal) * (win.placed ? 1 : 0)
                opacity: win.reveal > 0.001 ? 1 : 0
                transformOrigin: Item.Center

                // A new size (a different scale, a different monitor) keeps the card on
                // screen; not while it is being dragged, then the drag owns the position.
                onWidthChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                onHeightChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                // The housing: the same navy outline / pale ring / surface fill / hard
                // shadow as the bar, the dock, the To-Do card and the clock.
                // Not drawn at 1 x 1: that size is one bare object on the wallpaper (TinyFoot.qml).
                Pill {
                    visible: !card.tiny
                    anchors.fill: parent
                    cornerRadius: mt.radiusOuter
                    ringWidth: mt.borderWidth + mt.outerRingWidth
                    ringColorTop: mt.pSurfaceRing
                    ringColorBottom: ringColorTop
                    fillColor: mt.pSurface
                }

                // Edit Desktop: outline, corner diamonds, a tag and a drag shield
                // (EditChrome.qml). Draws nothing outside the mode.
                EditChrome {
                    id: chrome
                    widgetId: "calendarcard"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("calendarcard", win.screen ? win.screen.name : "")
                }

                // Left button: drag the card on the normal desktop, unless Lock all is on
                // (EditMode.desktopDragAllowed; while editing, the shield in EditChrome.qml
                // does the moving instead, until the card is selected for editing: then this
                // does). Sits UNDER the content, so the keys, the days and the cards win their
                // own clicks and everything else is "grab here".
                MouseArea {
                    id: dragArea
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    // The 1 x 1 keycap lights up when pointed at.
                    hoverEnabled: card.tiny
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    // Remember the new spot when a drag ends (also when it is cut short). A
                    // plain click doesn't save anything.
                    drag.onActiveChanged: {
                        chrome.ownDrag = drag.active
                        if (!drag.active)
                            win.saveSpot(card.x, card.y)
                    }

                    // A click on the bare card takes the keyboard back from a box.
                    onPressed: card.forceActiveFocus()
                }

                // Edit Desktop: step through FULL, 2 x 2 and 1 x 1 (only while the card is selected).
                SizeKey {
                    shown: chrome.selected
                    small: card.tiny
                    label: "SIZE  " + (card.tiny ? "1 x 1" : (card.small ? "2 x 2" : "FULL"))
                    onToggled: CalendarCardService.toggleSize()
                }

                // ===== the content =====
                Item {
                    id: content
                    z: 2
                    visible: !card.small && !card.tiny
                    x: card.inset
                    y: card.inset
                    width: card.contentW
                    height: card.contentH

                    Column {
                        id: col
                        width: card.contentW
                        spacing: 8

                        // ===== the plate, and the tally hanging off it =====
                        Item {
                            id: head
                            width: card.contentW
                            height: 102

                            SekaiPlate {
                                id: plate
                                width: head.width
                                height: 88

                                // The line above the month: the day you point at, or the year.
                                Text {
                                    x: 14
                                    y: 9
                                    width: 190
                                    elide: Text.ElideRight
                                    color: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.82)
                                    font.family: mt.fontFamily
                                    font.pixelSize: Math.round(10.5)
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 0.3
                                    text: {
                                        if (win.hoverCell) {
                                            const n = (win.byDay[win.hoverCell.key] || []).length
                                            return CM.longDay(win.hoverCell.y, win.hoverCell.m, win.hoverCell.d)
                                                + "  \u00b7  " + (n === 0 ? "free" : n + (n === 1 ? " entry" : " entries"))
                                        }
                                        return win.viewYear + (win.monthShift === 0
                                            ? "  \u00b7  Week " + CM.isoWeek(win.today.getFullYear(), win.today.getMonth(), win.today.getDate())
                                            : "")
                                    }
                                }

                                StickerText {
                                    x: 6
                                    y: 20
                                    text: CM.monthName(win.viewMonth)
                                    pixelSize: 34
                                    fillColor: plate.numberFill
                                    ringColor: plate.numberRing
                                }

                                // Today, as a tilted dark disc: click and the card turns back to it.
                                Pill {
                                    id: disc
                                    x: plate.width - width - 12
                                    y: 8
                                    width: 62
                                    height: 66
                                    cornerRadius: 31
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    shadowDy: 4
                                    rotation: 6
                                    transformOrigin: Item.Center
                                    pressed: discArea.pressed
                                    fillColor: mt.chipFill

                                    property real sx: 1
                                    property real sy: 1

                                    transform: Scale {
                                        origin.x: disc.width / 2
                                        origin.y: disc.height / 2
                                        xScale: disc.sx
                                        yScale: disc.sy
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: -3

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: CM.weekdayShort(win.today.getDay())
                                            color: mt.dark ? mt.accentMint : mt.chipInk
                                            font.family: mt.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.ExtraBold
                                            font.styleName: mt.fontStyleBold
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: String(win.today.getDate())
                                            color: mt.chipInk
                                            font.family: mt.fontFamily
                                            font.pixelSize: 28
                                            font.weight: Font.ExtraBold
                                            font.styleName: mt.fontStyleBold
                                        }
                                    }
                                }

                                SequentialAnimation {
                                    id: squish
                                    ParallelAnimation {
                                        NumberAnimation { target: disc; property: "sx"; to: 1.18; duration: 80; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: disc; property: "sy"; to: 0.82; duration: 80; easing.type: Easing.OutQuad }
                                    }
                                    ParallelAnimation {
                                        NumberAnimation { target: disc; property: "sx"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                        NumberAnimation { target: disc; property: "sy"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                    }
                                }

                                MouseArea {
                                    id: discArea
                                    x: disc.x
                                    y: disc.y
                                    width: disc.width
                                    height: disc.height
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        squish.restart()
                                        puff.fire()
                                        win.goToday()
                                    }
                                }

                                Burst {
                                    id: puff
                                    x: disc.x + disc.width / 2
                                    y: disc.y + disc.height / 2
                                    radius: 54
                                    count: 8
                                }
                            }

                            // The month's tally, hanging off the plate's lower edge.
                            Text {
                                id: tallyProbe
                                visible: false
                                text: tab.label
                                font.family: mt.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            Slant {
                                id: tab
                                readonly property string label: {
                                    const s = win.summary
                                    if (s.events === 0)
                                        return "Nothing planned"
                                    let t = s.events + (s.events === 1 ? " entry" : " entries")
                                    if (s.late > 0)
                                        t += "  \u00b7  " + s.late + " late"
                                    else if (s.open > 0)
                                        t += "  \u00b7  " + s.open + " due"
                                    return t
                                }
                                x: 2
                                y: 74
                                width: Math.min(tallyProbe.implicitWidth + 44 + height * skew, 188)
                                height: 26
                                skew: 0.2
                                radius: 9
                                color: win.summary.late > 0 ? win.alertInk : mt.chipFill
                                borderColor: mt.pLine
                                borderWidth: 3
                            }

                            // Text goes NEXT to the Slant (a child would lean with it).
                            Row {
                                x: tab.x + tab.lean / 2 + 10
                                y: tab.y
                                height: tab.height
                                spacing: 4

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: win.summary.late > 0 ? "flag" : "event"
                                    fill: win.summary.late > 0 ? 1 : 0
                                    size: 15
                                    weight: 700
                                    color: win.summary.late > 0 ? win.alertText : (mt.dark ? mt.accentMint : mt.colBorder)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, tab.width - tab.lean - 36)
                                    elide: Text.ElideRight
                                    text: tab.label
                                    color: win.summary.late > 0 ? win.alertText : mt.chipInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }
                            }

                            CalendarNavKey {
                                x: head.width - 34 - 6 - 34
                                y: 71
                                icon: "chevron_left"
                                onClicked: win.page(-1)
                            }

                            CalendarNavKey {
                                x: head.width - 34
                                y: 71
                                icon: "chevron_right"
                                onClicked: win.page(1)
                            }
                        }

                        // ===== the weekday strip =====
                        Row {
                            id: weekRow
                            spacing: 3

                            Repeater {
                                model: win.weekdays

                                Text {
                                    required property string modelData
                                    required property int index
                                    width: 42
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    // The weekend columns (Saturday = 6, Sunday = 0).
                                    readonly property int dow: (win.firstDay + index) % 7
                                    color: dow === 0 || dow === 6 ? win.weekendInk : mt.pInkSub
                                    font.family: mt.fontFamily
                                    font.pixelSize: Math.round(10.5)
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }
                            }
                        }

                        // ===== the days =====
                        Item {
                            id: grid
                            width: card.contentW
                            height: 6 * 32 + 5 * 3

                            // The wheel over the days pages the months, a notch at a time.
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: event => {
                                    if (wheelPause.running)
                                        return
                                    wheelPause.restart()
                                    win.page(event.angleDelta.y > 0 ? -1 : 1)
                                }
                            }

                            Timer {
                                id: wheelPause
                                interval: 160
                            }

                            Repeater {
                                model: win.cells

                                Item {
                                    id: cell
                                    required property var modelData
                                    required property int index
                                    readonly property var c: cell.modelData
                                    readonly property var entries: win.byDay[cell.c.key] || []
                                    readonly property int diff: EM.diffTo(win.today, cell.c.key)
                                    readonly property var marks: EM.dayMarks(cell.entries, cell.diff, 3)
                                    readonly property bool selected: win.selectedKey === cell.c.key
                                    readonly property bool hovered: win.hoverIndex === cell.index
                                    readonly property bool raised: cell.c.isToday || cell.selected
                                    // This cell's turn in the page-turn cascade (row by row).
                                    readonly property real wave: Math.max(0, Math.min(1,
                                        (win.gridWave * win.gridWaveMs - cell.c.row * 45 - cell.c.col * 12) / 240))

                                    x: cell.c.col * 45
                                    y: cell.c.row * 35
                                    width: 42
                                    height: 32
                                    scale: (0.6 + 0.4 * CM.outBack(cell.wave, 1.8)) * (cell.hovered ? 1.05 : 1)
                                    opacity: Math.min(1, cell.wave * 3)
                                    transformOrigin: Item.Center

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    // The key's hard shadow, under today and the day you picked.
                                    Rectangle {
                                        visible: cell.raised
                                        x: 0
                                        y: 2
                                        width: parent.width
                                        height: parent.height
                                        radius: 9
                                        color: mt.pLineShadow
                                        antialiasing: true
                                    }

                                    Rectangle {
                                        id: keycap
                                        width: parent.width
                                        height: parent.height - (cell.raised ? 2 : 0)
                                        radius: 9
                                        antialiasing: true
                                        border.width: cell.raised ? 2.5 : 0
                                        border.color: mt.pLine
                                        color: {
                                            const base = cell.hovered ? mt.pSurfaceHover : (cell.c.inMonth ? mt.pSurfaceHover : "transparent")
                                            if (cell.marks.count > 0)
                                                return win.wash(cell.c.inMonth ? mt.pSurfaceHover : mt.pSurface,
                                                                win.attr(cell.marks.colors[0]), cell.c.inMonth ? 0.55 : 0.22)
                                            return base
                                        }
                                        gradient: cell.c.isToday ? accentGradient : null
                                    }

                                    Text {
                                        x: 0
                                        y: 3
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: String(cell.c.d)
                                        opacity: cell.c.inMonth ? 1 : 0.42
                                        color: cell.c.isToday ? mt.colBorder : (cell.c.isWeekend ? win.weekendInk : mt.pInk)
                                        font.family: mt.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                    }

                                    // One diamond per colour the day holds (three at most).
                                    Row {
                                        visible: cell.marks.count > 0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: parent.height - 12
                                        spacing: 5

                                        Repeater {
                                            model: cell.marks.colors

                                            Rectangle {
                                                required property int modelData
                                                width: 6.5
                                                height: 6.5
                                                radius: 1.5
                                                rotation: 45
                                                antialiasing: true
                                                color: win.attr(modelData)
                                                border.width: 1.5
                                                border.color: mt.pLine
                                                opacity: cell.c.inMonth ? 1 : 0.6
                                            }
                                        }
                                    }

                                    // An open deadline on the day: a flag in the corner.
                                    MaterialIcon {
                                        visible: cell.marks.deadline !== ""
                                        x: parent.width - width - 2
                                        y: 1
                                        name: "flag"
                                        size: 11
                                        weight: 700
                                        fill: 1
                                        color: win.stateInk(cell.marks.deadline)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: win.hoverIndex = cell.index
                                        onExited: {
                                            if (win.hoverIndex === cell.index)
                                                win.hoverIndex = -1
                                        }
                                        onClicked: win.clickDay(cell.c)
                                        onDoubleClicked: {
                                            if (!win.forming)
                                                win.openForm("", cell.c.key)
                                        }
                                    }
                                }
                            }
                        }

                        // ===== what the list below is =====
                        Item {
                            id: sectionHead
                            width: card.contentW
                            height: 30

                            Column {
                                anchors.left: parent.left
                                anchors.right: sectionKeys.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: {
                                        if (win.forming)
                                            return win.formId === "" ? "New entry" : "Edit entry"
                                        if (win.selectedKey !== "") {
                                            const p = EM.parseDate(win.selectedKey)
                                            return p ? CM.longDay(p.y, p.m, p.d) : ""
                                        }
                                        return "Coming up"
                                    }
                                    color: mt.pInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 15
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: {
                                        if (win.forming) {
                                            const p = EM.parseDate(win.selectedKey)
                                            return (p ? CM.longDay(p.y, p.m, p.d) + "  \u00b7  " : "") + "click a day to move it"
                                        }
                                        const n = win.shownList.length
                                        if (win.selectedKey !== "")
                                            return CM.relative(win.selectedDiff) + "  \u00b7  "
                                                + (n === 0 ? "nothing on" : n + (n === 1 ? " entry" : " entries"))
                                        return n === 0 ? "nothing yet" : n + (n === 1 ? " entry ahead" : " entries ahead")
                                    }
                                    color: mt.pInkSub
                                    font.family: mt.fontFamily
                                    font.pixelSize: Math.round(10.5)
                                    font.weight: Font.DemiBold
                                }
                            }

                            Row {
                                id: sectionKeys
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                // Back to "Coming up" from one day.
                                CalendarChip {
                                    visible: win.selectedKey !== "" && !win.forming
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: "close"
                                    label: "All"
                                    onClicked: {
                                        win.selectedKey = ""
                                        win.expandedId = ""
                                    }
                                }

                                // Add one (to the day picked, or today).
                                Rectangle {
                                    id: addBtn
                                    visible: !win.forming
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    height: 30
                                    radius: 10
                                    border.width: 2.5
                                    border.color: mt.pLine
                                    opacity: CalendarCardService.full ? 0.45 : 1
                                    scale: addArea.pressed ? 0.9 : 1
                                    gradient: accentGradient

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    MaterialIcon {
                                        color: mt.colBorder
                                        anchors.centerIn: parent
                                        name: "add"
                                        size: 20
                                        weight: 700
                                    }

                                    MouseArea {
                                        id: addArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.openForm("", win.selectedKey)
                                    }
                                }
                            }
                        }

                        // ===== the list or the form (the same height, so the card never jumps) =====
                        Item {
                            id: region
                            width: card.contentW
                            height: 180

                            WheelScroll { scroller: list }
                            ListView {
                                id: list
                                anchors.fill: parent
                                visible: !win.forming
                                clip: true
                                spacing: 6
                                bottomMargin: 4
                                boundsBehavior: Flickable.StopAtBounds
                                model: win.shownList

                                // Where the list was before an edit changed it, so a tick or a
                                // delete does not throw you back to the top (-1 = no edit).
                                property real keepY: -1

                                delegate: CalendarEventCard {
                                    today: win.today
                                    use24h: ClockService.use24h
                                    alertInk: win.alertInk
                                    alertText: win.alertText
                                    soonInk: win.soonInk
                                    expanded: win.expandedId === modelData.id
                                    onToggled: win.expandedId = win.expandedId === modelData.id ? "" : modelData.id
                                    onDoneToggled: win.toggleDone(modelData)
                                    onEditRequested: win.openForm(modelData.id, "")
                                    onDeleteRequested: win.deleteEvent(modelData)
                                }

                                onModelChanged: {
                                    if (list.keepY >= 0) {
                                        const y = list.keepY
                                        list.keepY = -1
                                        Qt.callLater(() => list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height)))
                                    }
                                }

                                SekaiScrollBar {}
                            }

                            // Nothing to list.
                            Column {
                                visible: !win.forming && win.shownList.length === 0
                                anchors.centerIn: parent
                                spacing: 3

                                MaterialIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: "event_available"
                                    size: 30
                                    weight: 500
                                    fill: 0
                                    color: mt.pInkSub
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: win.selectedKey !== "" ? "Nothing on this day" : "No events yet"
                                    color: mt.pInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Press + or double-click a day to add one"
                                    color: mt.pInkSub
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            // ===== the form =====
                            Column {
                                id: form
                                visible: win.forming
                                width: parent.width
                                spacing: 6

                                CalendarField {
                                    id: titleField
                                    width: form.width
                                    hint: "Title"
                                    badInk: win.alertInk
                                    icon: "title"
                                    onAccepted: win.saveForm()
                                    onCancelled: win.closeForm()
                                }

                                CalendarField {
                                    id: noteField
                                    width: form.width
                                    hint: "Note (optional)"
                                    icon: "notes"
                                    onAccepted: win.saveForm()
                                    onCancelled: win.closeForm()
                                }

                                Row {
                                    spacing: 8
                                    height: 32

                                    CalendarField {
                                        id: timeField
                                        width: 104
                                        height: 32
                                        hint: "All day"
                                        icon: "schedule"
                                        bad: win.formTime === null
                                        badInk: win.alertInk
                                        onAccepted: win.saveForm()
                                        onCancelled: win.closeForm()
                                    }

                                    // Event or deadline.
                                    Repeater {
                                        model: [
                                            { kind: "event", label: "Event", icon: "event" },
                                            { kind: "deadline", label: "Deadline", icon: "flag" }
                                        ]

                                        Rectangle {
                                            required property var modelData
                                            readonly property bool chosen: win.formKind === modelData.kind
                                            width: (form.width - 104 - 16) / 2
                                            height: 32
                                            radius: 11
                                            border.width: 2.5
                                            border.color: mt.pLine
                                            color: chosen ? mt.accentMint : (kindArea.containsMouse ? mt.pSurfaceHover : mt.pSurface)
                                            gradient: chosen ? accentGradient : null

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                MaterialIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: modelData.icon
                                                    size: 15
                                                    weight: 700
                                                    fill: chosen ? 1 : 0
                                                    color: chosen ? mt.colBorder : mt.pInk
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.label
                                                    color: chosen ? mt.colBorder : mt.pInk
                                                    font.family: mt.fontFamily
                                                    font.pixelSize: Math.round(11.5)
                                                    font.weight: Font.ExtraBold
                                                    font.styleName: mt.fontStyleBold
                                                }
                                            }

                                            MouseArea {
                                                id: kindArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.formKind = modelData.kind
                                            }
                                        }
                                    }
                                }

                                // The five attribute colours.
                                Row {
                                    spacing: 14
                                    height: 24
                                    leftPadding: 10

                                    Repeater {
                                        model: 5

                                        Item {
                                            required property int index
                                            readonly property bool chosen: win.formColor === index
                                            width: 22
                                            height: 24

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 15
                                                height: 15
                                                radius: 3.5
                                                rotation: 45
                                                antialiasing: true
                                                scale: chosen ? 1.3 : (swatchArea.containsMouse ? 1.12 : 1)
                                                color: win.attr(index)
                                                border.width: chosen ? 3 : 2
                                                border.color: mt.pLine

                                                Behavior on scale {
                                                    NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                                }
                                            }

                                            MouseArea {
                                                id: swatchArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.formColor = index
                                            }
                                        }
                                    }

                                    // The colour's name (Project SEKAI's five attributes).
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ["Cool", "Cute", "Happy", "Mysterious", "Pure"][win.formColor]
                                        color: mt.pInkSub
                                        font.family: mt.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                    }
                                }

                                Row {
                                    spacing: 8
                                    height: 32

                                    CalendarChip {
                                        height: 32
                                        primary: true
                                        usable: win.formValid
                                        icon: "check"
                                        label: win.formId === "" ? "Add" : "Save"
                                        onClicked: win.saveForm()
                                    }

                                    CalendarChip {
                                        height: 32
                                        icon: "close"
                                        label: "Cancel"
                                        onClicked: win.closeForm()
                                    }
                                }
                            }
                        }
                    }
                }

                // ===== the 1 x 1 face =====
                // Today's day and date printed on a keycap (CalendarTile.qml). Nothing on it is
                // clickable: it is the card's drag area underneath, so it moves like any other.
                Loader {
                    id: tinyLoader
                    z: 2
                    x: card.inset
                    y: card.inset
                    active: card.tiny
                    sourceComponent: tinyFace
                }

                Component {
                    id: tinyFace

                    CalendarTile {
                        width: card.contentW
                        height: card.contentH
                        today: win.today
                        hover: dragArea.containsMouse
                        pressed: dragArea.pressed
                    }
                }

                // ===== the 2 x 2 face =====
                // The same card in the 320 x 276 footprint: a short plate with the month and
                // the two page keys, the weekday strip, and the month's days with the same
                // marks (washed days, up to three diamonds, a flag for an open deadline).
                // There is no list and no form on it; the full card has them. Pointing at a
                // day reads it out on the plate, a click on a faded day turns to its month,
                // the month name (or the wheel) pages and returns to today. The size never
                // changes by itself: a double-click on a day does nothing here (to add an
                // entry, switch the card to its full size yourself).
                Loader {
                    id: miniLoader
                    z: 2
                    x: card.inset
                    y: card.inset
                    active: card.small
                    sourceComponent: miniFace
                }

                Component {
                    id: miniFace

                    Item {
                        id: mini
                        width: card.contentW
                        height: card.contentH

                        // ----- the plate: month, year / week, page keys -----
                        SekaiPlate {
                            id: miniPlate
                            width: mini.width
                            height: 62

                            Text {
                                x: 14
                                y: 6
                                width: 176
                                elide: Text.ElideRight
                                color: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.82)
                                font.family: mt.fontFamily
                                font.pixelSize: Math.round(10.5)
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                                font.letterSpacing: 0.3
                                text: {
                                    if (win.hoverCell) {
                                        const n = (win.byDay[win.hoverCell.key] || []).length
                                        return CM.longDay(win.hoverCell.y, win.hoverCell.m, win.hoverCell.d)
                                            + "  \u00b7  " + (n === 0 ? "free" : n + (n === 1 ? " entry" : " entries"))
                                    }
                                    const sm = win.summary
                                    return win.viewYear + (win.monthShift === 0
                                            ? "  \u00b7  Week " + CM.isoWeek(win.today.getFullYear(), win.today.getMonth(), win.today.getDate())
                                            : "")
                                        + (sm.events > 0 ? "  \u00b7  " + sm.events + (sm.events === 1 ? " entry" : " entries") : "")
                                }
                            }

                            StickerText {
                                id: miniMonth
                                x: 6
                                y: 12
                                text: CM.monthName(win.viewMonth)
                                pixelSize: 26
                                fillColor: miniPlate.numberFill
                                ringColor: miniPlate.numberRing
                            }

                            // The month name takes you back to today.
                            MouseArea {
                                x: miniMonth.x
                                y: miniMonth.y
                                width: miniMonth.width
                                height: miniMonth.height
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.goToday()
                            }

                            CalendarNavKey {
                                x: miniPlate.width - 34 - 6 - 34 - 12
                                y: 12
                                icon: "chevron_left"
                                onClicked: win.page(-1)
                            }

                            CalendarNavKey {
                                x: miniPlate.width - 34 - 12
                                y: 12
                                icon: "chevron_right"
                                onClicked: win.page(1)
                            }
                        }

                        // ----- the weekday strip -----
                        Row {
                            x: 1
                            y: 66
                            spacing: 3

                            Repeater {
                                model: win.weekdays

                                Text {
                                    required property string modelData
                                    required property int index
                                    width: 38
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    // The weekend columns (Saturday = 6, Sunday = 0).
                                    readonly property int dow: (win.firstDay + index) % 7
                                    color: dow === 0 || dow === 6 ? win.weekendInk : mt.pInkSub
                                    font.family: mt.fontFamily
                                    font.pixelSize: Math.round(10.5)
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }
                            }
                        }

                        // ----- the days: always six rows, so the card never changes height -----
                        Item {
                            id: miniGrid
                            y: 82
                            width: mini.width
                            height: 6 * 24 + 5 * 2

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: event => {
                                    if (miniWheelPause.running)
                                        return
                                    miniWheelPause.restart()
                                    win.page(event.angleDelta.y > 0 ? -1 : 1)
                                }
                            }

                            Timer {
                                id: miniWheelPause
                                interval: 160
                            }

                            Repeater {
                                model: win.cells

                                Item {
                                    id: mcell
                                    required property var modelData
                                    required property int index
                                    readonly property var c: mcell.modelData
                                    readonly property var entries: win.byDay[mcell.c.key] || []
                                    readonly property int diff: EM.diffTo(win.today, mcell.c.key)
                                    readonly property var marks: EM.dayMarks(mcell.entries, mcell.diff, 3)
                                    readonly property bool hovered: win.hoverIndex === mcell.index
                                    readonly property bool raised: mcell.c.isToday
                                    // This cell's turn in the page-turn cascade (row by row).
                                    readonly property real wave: Math.max(0, Math.min(1,
                                        (win.gridWave * win.gridWaveMs - mcell.c.row * 45 - mcell.c.col * 12) / 240))

                                    x: 1 + mcell.c.col * 41
                                    y: mcell.c.row * 26
                                    width: 38
                                    height: 24
                                    scale: (0.6 + 0.4 * CM.outBack(mcell.wave, 1.8)) * (mcell.hovered ? 1.05 : 1)
                                    opacity: Math.min(1, mcell.wave * 3)
                                    transformOrigin: Item.Center

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    // Today's key has the hard shadow under it.
                                    Rectangle {
                                        visible: mcell.raised
                                        x: 0
                                        y: 2
                                        width: parent.width
                                        height: parent.height
                                        radius: 8
                                        color: mt.pLineShadow
                                        antialiasing: true
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: parent.height - (mcell.raised ? 2 : 0)
                                        radius: 8
                                        antialiasing: true
                                        border.width: mcell.raised ? 2 : 0
                                        border.color: mt.pLine
                                        color: {
                                            const base = mcell.hovered ? mt.pSurfaceHover : (mcell.c.inMonth ? mt.pSurfaceHover : "transparent")
                                            if (mcell.marks.count > 0)
                                                return win.wash(mcell.c.inMonth ? mt.pSurfaceHover : mt.pSurface,
                                                                win.attr(mcell.marks.colors[0]), mcell.c.inMonth ? 0.55 : 0.22)
                                            return base
                                        }
                                        gradient: mcell.c.isToday ? accentGradient : null
                                    }

                                    Text {
                                        x: 0
                                        y: 2
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: String(mcell.c.d)
                                        opacity: mcell.c.inMonth ? 1 : 0.42
                                        color: mcell.c.isToday ? mt.colBorder : (mcell.c.isWeekend ? win.weekendInk : mt.pInk)
                                        font.family: mt.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                    }

                                    // One diamond per colour the day holds (three at most).
                                    Row {
                                        visible: mcell.marks.count > 0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: parent.height - 9
                                        spacing: 4

                                        Repeater {
                                            model: mcell.marks.colors

                                            Rectangle {
                                                required property int modelData
                                                width: 5
                                                height: 5
                                                radius: 1
                                                rotation: 45
                                                antialiasing: true
                                                color: win.attr(modelData)
                                                border.width: 1
                                                border.color: mt.pLine
                                                opacity: mcell.c.inMonth ? 1 : 0.6
                                            }
                                        }
                                    }

                                    // An open deadline on the day: a flag in the corner.
                                    MaterialIcon {
                                        visible: mcell.marks.deadline !== ""
                                        x: parent.width - width - 1
                                        y: 0
                                        name: "flag"
                                        size: 9
                                        weight: 700
                                        fill: 1
                                        color: win.stateInk(mcell.marks.deadline)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: win.hoverIndex = mcell.index
                                        onExited: {
                                            if (win.hoverIndex === mcell.index)
                                                win.hoverIndex = -1
                                        }
                                        onClicked: win.showMonthOf(mcell.c)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }

    // Asks for the keyboard only under the pointer or while typing (issue #72).
    KeysOnPoint {
        id: keys
    }
}
