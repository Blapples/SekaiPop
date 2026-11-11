import QtQuick
import Quickshell
import qs.services
import "Calc.js" as Calc
import "../../common/functions/Extras.js" as X
import qs.modules.common
import qs.modules.common.widgets

// What the old Overview + App Launcher board could do beyond launching apps, now
// on the Apps screen of the phone (LauncherFace.qml hosts this; the board is gone).
// The rules are the same ones (Extras.js, ExtrasSource.qml, Calc.js); only the place
// is new. Type into the Apps search box:
//
//   calc / calculator, or just a sum   CalculatorCard.qml   pressable calculator
//   clip / clipboard / cb              ClipboardCard.qml    history: list left, full text right
//   color / colour, or #ff8800         ColorCard.qml        real swatch, formats, eyedropper
//   emoji / emo / :smile               EmojiCard.qml        the usual picker
//   web / ? / g / ddg / yt / gh / wiki WebCard.qml          browser-style web search
//   > cmd    run a shell command (background)   $ cmd   run it in a terminal
//   lock, reboot, dark mode, ...       system actions, as rows above the apps
//   anything that matches nothing      a "Search the web for ..." row
//
// A card takes the page the app grid is on while the box asks for it; the rows (system
// actions, a command, the web row) sit above the grid. The destructive actions (power,
// log out, wipe) ask for Enter a second time, as before.
//
// Pure UI plus ExtrasSource.qml (the system side): it never closes the phone itself, it
// asks (`doneRequested`) and QuickPanel.qml does it.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // ===== given =====
    // The Apps search box's text.
    property string query: ""
    // The Apps screen is up (the clipboard history and the web suggestions only run
    // while it is).
    property bool active: false
    // The Apps screen is still on show, even if it is already on its way out (or has not
    // started to come in): the card stays built while it fades away with the screen instead
    // of vanishing the moment the screen is asked to go. (`active` is the data side: the
    // clipboard history and the web suggestions only run while the screen is really up.)
    property bool present: false
    // How many apps match the text, so the web row knows when nothing at all does.
    property int appCount: 0
    // The room the page has (design units).
    property real pageWidth: 550
    property real pageHeight: 700

    // ===== asks =====
    // Something was run or copied: the phone should go away.
    signal doneRequested()
    // Put this in the search box (the calculator's keys, a colour shade).
    signal setTextRequested(string text)
    // The eyedropper needs the screen to itself: the phone goes away, and when a colour
    // is picked it asks for the phone back on the colour card.
    signal pickerRequested()
    signal colorPicked(string hex)

    readonly property alias source: extras

    ExtrasSource {
        id: extras
        query: root.query
        active: root.active

        onColorPicked: hex => {
            extras.copyText(hex)
            root.colorPicked(hex)
        }
    }

    // ===== which card, which rows =====
    readonly property string cardMode: [ "calc", "clip", "color", "emoji", "web" ].indexOf(extras.mode) >= 0 ? extras.mode : ""
    readonly property bool cardShown: cardMode !== ""

    // The card that is on the page. It is `cardMode` while one is asked for, and is kept for
    // a moment after the box stops asking so the card can fade away; without this the card
    // was destroyed in the same frame the text changed.
    property string shownMode: ""
    onCardModeChanged: {
        if (root.cardMode !== "") {
            holdTimer.stop()
            root.shownMode = root.cardMode
        } else if (root.shownMode !== "") {
            holdTimer.restart()
        }
    }
    Component.onCompleted: root.shownMode = root.cardMode
    onPresentChanged: {
        // Nothing on show any more: drop it now (nothing is left to fade).
        if (!root.present && !root.active && root.cardMode === "") {
            holdTimer.stop()
            root.shownMode = ""
        }
    }
    Timer {
        id: holdTimer
        interval: 150
        onTriggered: {
            if (root.cardMode === "")
                root.shownMode = ""
        }
    }

    // 0 = the apps grid has the page, 1 = a card has it. It glides (the grid fades out as
    // the card fades in) while the screen is on show; with the screen out of sight it just
    // takes its value, so a card asked for while the phone is still coming up is there
    // already. LauncherFace reads it for the grid.
    property real cardK: root.cardMode !== "" ? 1 : 0
    Behavior on cardK {
        enabled: root.present && root.active
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    // System actions that match ("lock", "dark mode"), a command row for "> cmd", or
    // a "Search the web" row when nothing matches at all. `strong` are the ones that
    // match the start of their name: they have the pick, ahead of the apps.
    readonly property var rowsAll: {
        if (root.cardMode !== "")
            return { rows: [], strong: 0 }
        if (extras.mode === "shell")
            return { rows: extras.listEntries, strong: extras.listEntries.length }
        const above = [], below = []
        for (const m of extras.actionMatches)
            (m.score >= 80 ? above : below).push(extras.actionEntry(m.action))
        const q = root.query.trim()
        if (above.length + below.length === 0 && root.appCount === 0 && q.length > 0)
            return {
                rows: [ { isAction: true, id: "websearch", kind: "web", title: "Search the web for \u201c" + q + "\u201d",
                          sub: "Opens in your browser", glyph: "travel_explore", confirm: false } ],
                strong: 1
            }
        return { rows: above.concat(below), strong: above.length }
    }
    readonly property var rows: rowsAll.rows
    readonly property int strongRows: rowsAll.strong

    // The row that has the pick: -1 = none, the app grid has it.
    property int rowPick: -1
    // Which destructive action is waiting for its second Enter.
    property string pendingConfirm: ""

    // The rows that were showing, kept for a moment after there are none so they can fade
    // out while the grid glides back up (`rowsHold`).
    property var rowsHold: []
    onRowsChanged: {
        pendingConfirm = ""
        rowPick = strongRows > 0 ? 0 : -1
        if (rows.length > 0) {
            rowsHoldTimer.stop()
            rowsHold = rows.slice(0, maxRows)
        } else if (rowsHold.length > 0) {
            rowsHoldTimer.restart()
        }
    }
    Timer {
        id: rowsHoldTimer
        interval: 120
        onTriggered: {
            if (root.rows.length === 0)
                root.rowsHold = []
        }
    }
    onRowPickChanged: pendingConfirm = ""

    readonly property int rowH: 64
    readonly property int rowGap: 8
    readonly property int maxRows: 3
    readonly property int shownRows: Math.min(rows.length, maxRows)
    // How much room the rows take above the grid (0 with none).
    readonly property real rowsTarget: shownRows > 0 ? shownRows * rowH + (shownRows - 1) * rowGap + 14 : 0
    // ... and what the grid actually moves by: it glides to the new room instead of jumping
    // (it used to jump the moment the first row showed up or the last one went).
    property real rowsHeight: root.rowsTarget
    Behavior on rowsHeight {
        enabled: root.present && root.active
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    // ===== keys (LauncherFace.qml forwards them) =====
    // Up / Down / Left / Right in a card, or Up / Down over the rows. true = handled.
    function navigate(dx, dy) {
        if (root.cardMode !== "") {
            const it = cardLoader.item
            if (it && it.nav)
                it.nav(dx, dy)
            return true
        }
        return false
    }
   // Ctrl+Left / Ctrl+Right on the emoji card: previous / next category.
    // true = handled.
    function cycleCardTab(step) {
        if (root.cardMode !== "emoji")
            return false
            const it = cardLoader.item
            if (it && it.cycleTab)
                it.cycleTab(step)
                return true
    }
    // Down or Up while the rows are showing. `gridHasPick` / `gridOnFirstRow` come from
    // the face. Returns "grid" when the pick should go to the first app, "rows" when
    // it moved among the rows (or stayed), and "" when this has nothing to do with it.
    function moveRows(dy, gridHasPick, gridOnFirstRow) {
        const n = root.rows.length
        if (n === 0)
            return ""
        if (root.rowPick >= 0) {
            if (dy > 0) {
                if (root.rowPick < n - 1) {
                    root.rowPick++
                    return "rows"
                }
                if (root.appCount > 0) {
                    root.rowPick = -1
                    return "grid"
                }
                return "rows"
            }
            if (root.rowPick > 0)
                root.rowPick--
            return "rows"
        }
        if (dy < 0 && gridHasPick && gridOnFirstRow) {
            root.rowPick = Math.min(n, root.maxRows) - 1
            return "rows"
        }
        return ""
    }

    // Enter. true = it was ours (a card or a row), false = open the picked app.
    function enter(shift) {
        if (root.cardMode !== "") {
            const it = cardLoader.item
            if (it && it.activate)
                it.activate(shift)
            return true
        }
        if (root.rowPick >= 0 && root.rowPick < root.rows.length) {
            root.activateRow(root.rows[root.rowPick])
            return true
        }
        return false
    }

    // Ctrl+P on the clipboard card pins (or unpins) the picked entry. true = it was ours.
    function pinKey() {
        if (root.cardMode !== "clip")
            return false
        const it = cardLoader.item
        if (it && it.togglePin)
            it.togglePin()
        return true
    }

    // Tab on the web card changes the search engine.
    function tab(step) {
        if (root.cardMode !== "web")
            return false
        extras.cycleEngine(step)
        return true
    }

    // A system action or a command: destructive ones ask for Enter a second time.
    function activateRow(entry) {
        if (!entry)
            return
        if (entry.confirm && root.pendingConfirm !== entry.id) {
            root.pendingConfirm = entry.id
            return
        }
        root.pendingConfirm = ""
        if (entry.kind === "web") {
            extras.openUrl(X.searchUrl(0, root.query.trim()))
        } else if (entry.def && entry.def.special === "colorpick") {
            root.pickerRequested()
            extras.pickColor()
        } else {
            extras.run(entry)
        }
        root.doneRequested()
    }

    // ===== the calculator =====
    // The calculator's line is the text after "calc " in the box -- keys and typing
    // edit the same string. Typing a bare sum ("2+2") has no "calc " to keep, so the
    // first key press adds one (otherwise "C" would empty the box and the calculator
    // would vanish).
    property var calcHistory: []
    property bool calcFresh: false      // an answer was just worked out
    property bool calcSelf: false       // we are the ones changing the text

    readonly property string calcPrefix: extras.prefix === "" ? "calc " : extras.prefix

    function calcSet(arg) {
        root.calcSelf = true
        root.setTextRequested(root.calcPrefix + arg)
        root.calcSelf = false
    }

    Connections {
        target: extras
        function onArgChanged() {
            if (!root.calcSelf)
                root.calcFresh = false
        }
    }

    function calcInsert(t) {
        const arg = extras.arg
        const startsNew = /^[0-9.(]|^pi|^sqrt/.test(t)
        // right after "=", a digit starts a new sum; an operator carries on from the answer
        root.calcSet(root.calcFresh && startsNew ? t : arg + t)
        root.calcFresh = false
    }

    function calcBackspace() {
        const arg = extras.arg
        if (arg === "")
            return
        const stripped = arg.replace(/(sqrt\(|pi)$/, "")     // "sqrt(" and "pi" go as one key
        root.calcSet(stripped !== arg ? stripped : arg.slice(0, -1))
    }

    function calcClear() {
        root.calcSet("")
    }

    function calcEquals() {
        const arg = extras.arg.trim()
        const r = Calc.evaluate(arg)
        if (!r.ok)
            return
        if (arg === r.text) {              // already the answer: Enter again copies it
            extras.copyText(r.text)
            root.doneRequested()
            return
        }
        root.calcHistory = root.calcHistory.concat([{ expr: arg, result: r.text }]).slice(-30)
        root.calcSet(r.text)
        root.calcFresh = true
    }

    function calcCopy() {
        const r = Calc.evaluate(extras.arg)
        if (r.ok) {
            extras.copyText(r.text)
            root.doneRequested()
        }
    }

    function calcUse(i) {
        const h = root.calcHistory[i]
        if (h)
            root.calcSet(h.expr)
    }

    // Clipboard entries that match what's typed after "clip ". cliphist only hands over
    // the first ~100 characters of each entry as its preview, so that's what gets
    // searched; images match the word "image".
    readonly property var clipFiltered: {
        const f = extras.arg.trim().toLowerCase()
        if (f === "")
            return extras.clipEntries
        return extras.clipEntries.filter(e => e.image ? "image".indexOf(f) === 0 : e.preview.toLowerCase().indexOf(f) >= 0)
    }

    // ===== the card =====
    // Calc, Clip, Emoji and Web are phone cards (PhoneCard.qml): they are handed the
    // page's size and laid out for it, so they are never shrunk. Colour is still the
    // old paper card (ExtraFrame.qml) drawn at its own size and shrunk to fit the page
    // when it is bigger. Never enlarged.
    Loader {
        id: cardLoader

        readonly property real fit: item ? Math.min(1, root.pageWidth / item.width, root.pageHeight / item.height) : 1

        x: Math.round((root.pageWidth - (item ? item.width * fit : 0)) / 2)
        // Rises into place as it fades in (and sinks a little as it fades out).
        y: (1 - root.cardK) * 16
        opacity: root.cardK
        visible: opacity > 0.001
        // A card that is on its way out takes no more clicks or keys.
        enabled: root.cardMode !== ""
        // Built while the screen is on show, including the beat before it slides in (the
        // phone waits for the screen to be drawn before it moves), so the build does not
        // land in the first frames of the slide.
        active: (root.active || root.present) && root.shownMode !== ""
        sourceComponent: {
            switch (root.shownMode) {
            case "calc": return calcCard
            case "clip": return clipCard
            case "color": return colorCard
            case "emoji": return emojiCard
            case "web": return webCard
            }
            return null
        }
        onLoaded: {
            item.transformOrigin = Item.TopLeft
            item.scale = Qt.binding(() => cardLoader.fit)
            // A phone card takes the page's room; the paper cards have no pageH.
            if (item.pageH !== undefined) {
                item.pageW = Qt.binding(() => root.pageWidth)
                item.pageH = Qt.binding(() => root.pageHeight)
            }
        }
    }

    Component {
        id: calcCard
        CalculatorCard {
            expr: extras.arg
            history: root.calcHistory
            onInsert: t => root.calcInsert(t)
            onBackspace: root.calcBackspace()
            onClearAll: root.calcClear()
            onEquals: root.calcEquals()
            onCopyResult: root.calcCopy()
            onUseHistory: i => root.calcUse(i)
        }
    }

    Component {
        id: clipCard
        ClipboardCard {
            entries: root.clipFiltered
            available: extras.clipAvailable
            fullText: extras.clipFull
            fullImage: extras.clipImage
            loading: extras.clipLoading
            failed: extras.clipFailed
            error: extras.clipError
            filter: extras.arg.trim()
            onHighlighted: entry => extras.selectClip(entry)
            onCopyRequested: entry => {
                extras.copyClip(entry)
                root.doneRequested()
            }
            onDeleteRequested: entry => extras.deleteClip(entry)
            onPinRequested: entry => extras.togglePin(entry)
            onCloseRequested: root.doneRequested()
        }
    }

    Component {
        id: colorCard
        ColorCard {
            arg: extras.arg
            onCopyRequested: text => extras.copyText(text)
            onActivated: hex => {
                extras.copyText(hex)
                root.doneRequested()
            }
            onShadePicked: hex => root.setTextRequested(extras.prefix + hex)
            onPickRequested: {
                root.pickerRequested()
                extras.pickColor()
            }
        }
    }

    Component {
        id: emojiCard
        EmojiCard {
            arg: extras.arg
            recent: extras.recentEmoji
            onPicked: (emoji, typeIt) => {
                extras.copyText(emoji)
                extras.rememberEmoji(emoji)
                if (typeIt)
                    extras.typeText(emoji)
                root.doneRequested()
            }
        }
    }

    Component {
        id: webCard
        WebCard {
            arg: extras.arg
            engine: extras.engine
            suggestions: extras.suggestions
            onOpenRequested: url => {
                extras.openUrl(url)
                root.doneRequested()
            }
            onEngineChosen: index => extras.engineOverride = index
        }
    }

    // ===== the rows: system actions, a command, the web row =====
    Column {
        id: rowColumn

        width: root.pageWidth
        spacing: root.rowGap
        // Fades with the room it takes (a quick fade out, a little slower in).
        opacity: root.shownRows > 0 ? 1 : 0
        visible: opacity > 0.001
        enabled: root.shownRows > 0
        Behavior on opacity {
            enabled: root.present && root.active
            NumberAnimation {
                duration: root.shownRows > 0 ? 110 : 80
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            model: root.rowsHold

            delegate: Item {
                id: rowItem

                required property var modelData
                required property int index

                readonly property bool picked: root.rowPick === index
                readonly property bool confirming: root.pendingConfirm === modelData.id

                width: root.pageWidth
                height: root.rowH

                // The hard shadow the phone's buttons all have.
                Rectangle {
                    x: 4
                    y: 4
                    width: parent.width - 4
                    height: parent.height - 4
                    radius: height / 2
                    color: mt.pLineShadow
                    antialiasing: true
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 4
                    radius: height / 2
                    color: rowItem.confirming ? ScrapbookTheme.tapeCoral
                        : (rowItem.picked || rowArea.containsMouse) ? mt.accentMint : mt.pSurface
                    border.width: rowItem.picked || rowItem.confirming ? 5 : 3
                    border.color: mt.pLine
                    antialiasing: true

                    MaterialIcon {
                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        name: rowItem.modelData.glyph
                        size: 32
                        fill: 1
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 70
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            width: parent.width
                            text: rowItem.modelData.title
                            elide: Text.ElideRight
                            color: mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.ExtraBold
                        }

                        Text {
                            width: parent.width
                            text: rowItem.confirming ? "Press Enter again to confirm" : rowItem.modelData.sub
                            visible: text !== ""
                            elide: Text.ElideRight
                            color: mt.pInkSub
                            font.family: mt.fontFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                    }
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateRow(rowItem.modelData)
                }
            }
        }
    }
}
