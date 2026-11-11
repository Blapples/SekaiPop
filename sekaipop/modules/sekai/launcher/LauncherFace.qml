import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The screen of the launcher phone (LauncherPhone.qml): the shell's home
// screen. Same 654x1214 frame as the Quick Panel's face, so it sits in the same
// PhoneBody.
//
//   - a clock / date strip at the top (the notch is in the middle of it)
//   - a search pill: type anything and the Apps drawer takes over
//   - APPS: every installed app, A to Z or most used first (launcher.order), or the
//     ranked matches for what you typed
//
// There is no Home page, no Back chip and no Settings / Wallpapers tile: Settings is
// the gear on the Quick Panel and the Wallpapers have their own key.
//
// Keys: type to search, arrows move the pick, Enter opens it (the first match
// while searching), Escape clears the search, then asks to go back
// (closeRequested). Ctrl+1..4 jump to a screen of the phone (jumpRequested).
//
// It is the Apps screen of the one phone (QuickPanel.qml, PhoneRoute.js).
//
// What the old Overview + App Launcher board could do beyond launching apps (the
// calculator, clipboard, colour, emoji and web cards, `> cmd`, system actions like
// "lock") is here too, in LauncherExtras.qml, driven by the same search box.
//
// Pure UI apart from reading the app index it is given: it never launches
// anything itself, it asks (`appActivated`,
// `closeRequested`, `doneRequested`) and QuickPanel.qml does it.
Item {
    id: face

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // Keeps the classic (white) look in the first dark mode, like the Quick Panel,
    // Settings and Wallpapers screens; see Theme.classicFor. The tiles are Pills, and
    // Pill / MaterialIcon only use the phone's colours inside something that says so.
    readonly property bool classicPanel: true

    width: 654
    height: 1214

    // ===== what it is given =====
    // AppSource.qml: `ordered`, `rankEntries(query)` and `iconFor(name)`.
    property var source: null
    property string clockText: "00:00AM"
    property string dateText: "Sun, 20  Sep"
    // Internet speed, bytes per second (QuickSource.qml samples it): the same readout
    // as the Quick screen's, top-right.
    property real downloadBps: 0
    property real uploadBps: 0
    // Same idea as QuickPanelFace.renderScale (kept so a layer inside could use it).
    property real renderScale: 1
    // How far down the face (design units) is above the monitor's bottom edge.
    // The launcher phone only peeks out of the corner (like the Quick Panel), so
    // the page is laid out above this line; the whole face is 1214.
    property real visibleBottom: 1214
    // How far down the face the monitor edge reaches at most (the lower end of the
    // slanted cutoff, plus the pull-out bounce): the apps grid runs down to here, so
    // the apps scroll under the edge instead of being cut by an invisible line with
    // the wallpaper showing under them. Without it, the old stop 58 above the edge.
    property real visibleReach: face.visibleBottom + 58
    // The monitor the phone is up on (QuickPanel.targetScreen.name): its wallpaper is
    // the one drawn behind the apps (see the LCD wallpaper below).
    property string screenName: ""

    // ===== what it asks for =====
    signal appActivated(var app)
    // Escape with nothing left to undo here: go back one screen.
    signal closeRequested()
    // Ctrl+1..4 while typing: 1 Quick, 2 Apps, 3 Wallpapers, 4 Settings.
    signal jumpRequested(int number)
    // An extra was run or copied (an action, a command, a copied colour...): the phone
    // should go away.
    signal doneRequested()
    // The colour eyedropper needs the screen: the phone goes away; once a colour is
    // picked, `colorPickedBack` asks for the phone again on the colour card.
    signal pickerRequested()
    signal colorPickedBack(string hex)

    // ===== the layout (design units) =====
    readonly property real sideX: 52
    readonly property real gridW: 550
    readonly property int columns: 4
    readonly property real cellW: gridW / columns
    readonly property real cellH: 168

    // ===== state =====
    readonly property string query: input.text
    readonly property bool searching: query.trim().length > 0
    // The pick comes from the arrow keys (not the mouse): only then is one
    // tile picked out.
    property bool keyNav: false
    // The grid's pick is shown (the cursor plate behind a tile) whenever it is what
    // Enter would open: after the arrow keys moved it, and also while searching,
    // where Enter opens the first match even before an arrow key is pressed. Not
    // while a row above the grid (a system action, a command) or a card has Enter.
    readonly property bool gridPickShown: (keyNav || searching) && drawerGrid.currentIndex >= 0
        && extrasLayer.rowPick < 0 && !extrasLayer.cardShown

    // The grid used to come in each time the screen did: a quick rise and fade while
    // the phone was still sliding up under it. That is the expensive part of opening
    // the phone on Apps: the screen's picture is a big supersampled, multisampled
    // layer, and while nothing in it changes it is only moved (the Quick screen's
    // entry is that cheap). Fading the grid changed it on every frame of the slide,
    // so every frame redrew the whole screen *and* the phone around it. So the grid
    // is simply there with the phone now. true = the old rise and fade back.
    property bool reveal: false
    // 0 = just arrived, 1 = settled.
    property real revealT: 1
    onEnabledChanged: {
        // Opening the Apps screen: pick up apps installed since the list was built.
        if (enabled && source)
            source.sync()
        if (enabled && reveal) {
            revealT = 0
            revealAnim.restart()
        }
    }
    // A beat behind the phone, so the apps seem to arrive after it rather than with it.
    SequentialAnimation {
        id: revealAnim

        PauseAnimation {
            duration: 60
        }

        NumberAnimation {
            target: face
            property: "revealT"
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    function focusSearch() {
        input.forceActiveFocus()
        input.cursorPosition = input.text.length
    }

    // Letters typed on the Quick screen carry over into the search box. The text
    // is set even before this screen is visible (a hidden item cannot take the
    // keyboard yet; QuickPanel.qml hands it over once the screen has come in).
    function appendText(text) {
        input.text = input.text + text
        input.cursorPosition = input.text.length
    }

    // Replace what is typed (the calculator's keys, a colour shade).
    function setText(text) {
        input.text = text
        input.cursorPosition = input.text.length
        input.forceActiveFocus()
    }

    // Back to how it opens: all apps, nothing typed, nothing picked.
    function reset() {
        input.text = ""
        keyNav = false
        drawerGrid.currentIndex = -1
        drawerGrid.positionViewAtBeginning()
    }

    // Escape: one step back.
    function back() {
        if (input.text.length > 0)
            input.text = ""
        else
            face.closeRequested()
    }

    // What the grid shows: AppSource's own entry objects (built once, so the same app
    // is always the same object), every app in the chosen order or the ranked matches. Nothing is
    // copied or rebuilt here per letter typed.
    readonly property var drawerEntries: {
        if (!face.source)
            return []
        return face.searching ? face.source.rankEntries(face.query) : face.source.ordered
    }

    // The grid's model. A ScriptModel compares the new list with the old one by `key`
    // and only adds, removes and moves the tiles that really changed, so typing a
    // letter keeps the tiles of the apps that still match instead of throwing every
    // tile away and building them all again (what a plain array as the model does).
    ScriptModel {
        id: drawerModel

        values: face.drawerEntries
        objectProp: "key"
    }

    function activate(item) {
        if (!item)
            return
        if (item.app)
            face.appActivated(item.app)
    }

    // Whatever has the pick right now (the first match while searching).
    function activateCurrent() {
        const grid = drawerGrid
        let i = grid.currentIndex
        if (i < 0 && face.searching)
            i = 0
        if (i >= 0 && i < face.drawerEntries.length)
            face.activate(face.drawerEntries[i])
    }

    function moveKey(key) {
        // A card (calculator, emoji...) takes the arrows itself.
        if (extrasLayer.cardShown) {
            extrasLayer.navigate(key === Qt.Key_Left ? -1 : key === Qt.Key_Right ? 1 : 0,
                                 key === Qt.Key_Up ? -1 : key === Qt.Key_Down ? 1 : 0)
            return
        }
        // Rows above the grid (system actions, a command): Up / Down walk them first.
        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            const where = extrasLayer.moveRows(key === Qt.Key_Down ? 1 : -1,
                                               drawerGrid.currentIndex >= 0,
                                               drawerGrid.currentIndex >= 0 && drawerGrid.currentIndex < face.columns)
            if (where === "rows") {
                face.keyNav = true
                drawerGrid.currentIndex = -1
                return
            }
            if (where === "grid") {
                face.keyNav = true
                drawerGrid.currentIndex = 0
                return
            }
        }
        const grid = drawerGrid
        if (grid.count === 0)
            return
        face.keyNav = true
        if (grid.currentIndex < 0) {
            grid.currentIndex = 0
            return
        }
        if (key === Qt.Key_Left)
            grid.moveCurrentIndexLeft()
        else if (key === Qt.Key_Right)
            grid.moveCurrentIndexRight()
        else if (key === Qt.Key_Up)
            grid.moveCurrentIndexUp()
        else
            grid.moveCurrentIndexDown()
    }

    // New text: the pick starts on the first match.
    onQueryChanged: {
        drawerGrid.currentIndex = face.searching ? 0 : -1
        drawerGrid.positionViewAtBeginning()
        // Once the model has taken the new list as well.
        Qt.callLater(() => drawerGrid.positionViewAtBeginning())
    }

    // ===== the wallpaper, as an LCD (LauncherLcd.qml) =====
    // Settings -> General -> Quick Panel -> Phone wallpaper, the same one the Quick
    // screen shows (PanelImages.phoneWallpaperFor): the monitor's own wallpaper (a
    // video's first frame for a video wallpaper) or a picture of your own, under a fine
    // pixel mesh, in the shape of the phone's glass. Under everything below (z), and
    // not there at all with it off or while the picture is not known yet.
    readonly property string lcdPath: PanelImages.phoneWallpaperFor(face.screenName)

    // The wallpaper is shown near full strength, so the app names and "No apps match"
    // are white with a thin dark edge while it is there (no chip behind them). (The
    // header, clock + date + speed, changes its ink with the picture instead, like the
    // Quick screen's.)
    readonly property bool lcdOn: face.lcdPath !== ""

    LauncherLcd {
        id: lcdLayer

        z: -10
        x: mt.phoneScreenInset
        y: mt.phoneScreenInset
        width: face.width - 2 * mt.phoneScreenInset
        height: face.height - 2 * mt.phoneScreenInset
        path: face.lcdPath
        // A picture of your own is framed (Framing.js); the desktop's wallpaper is not.
        framing: PanelImages.phoneMode === "picture" ? PanelImages.framingFor("phone") : null
        renderScale: face.renderScale
        // Only decoded while this screen is the one showing.
        active: face.visible
    }

    // ===== top strip: clock + date + internet speed =====
    // The same header as the Quick screen's (QuickPanelFace.qml): same places, sizes and
    // fonts, and the same ink rule. With the LCD wallpaper behind it the ink goes white
    // where the picture is dark and the usual navy where it is light (LauncherLcd.qml
    // measures it); without, it is the plain panel ink. No chip behind any of it.
    readonly property color inkLeft: face.lcdOn ? (lcdLayer.darkLeft ? "#ffffff" : mt.colBorder) : mt.pInk
    readonly property color inkRight: face.lcdOn ? (lcdLayer.darkRight ? "#ffffff" : mt.colBorder) : mt.pInk

    Column {
        x: 67
        y: 36
        spacing: -7

        Text {
            text: face.clockText
            color: face.inkLeft
            font.family: mt.fontFamily
            font.pixelSize: 24
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Text {
            text: face.dateText
            color: face.inkLeft
            font.family: mt.fontFamily
            font.pixelSize: 20
        }
    }

    // Same as QuickPanelFace.formatRate.
    function formatRate(bps) {
        if (bps >= 1048576)
            return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024)
            return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    Column {
        id: speedBlock

        x: 654 - 67 - width
        y: 38
        width: 150
        spacing: -2

        Item {
            width: speedBlock.width
            height: downText.implicitHeight

            MaterialIcon {
                id: downIcon

                name: "arrow_downward"
                size: 20
                weight: 600
                color: face.inkRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: downText

                anchors.right: downIcon.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: face.formatRate(face.downloadBps)
                color: face.inkRight
                font.family: mt.fontFamily
                font.pixelSize: 20
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        Item {
            width: speedBlock.width
            height: upText.implicitHeight

            MaterialIcon {
                id: upIcon

                name: "arrow_upward"
                size: 20
                weight: 600
                color: face.inkRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: upText

                anchors.right: upIcon.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: face.formatRate(face.uploadBps)
                color: face.inkRight
                font.family: mt.fontFamily
                font.pixelSize: 20
            }
        }
    }

    // ===== search pill =====
    Rectangle {
        x: face.sideX + 4
        y: 124 + 4
        width: face.gridW
        height: 68
        radius: 34
        color: mt.pLineShadow
        antialiasing: true
    }

    Rectangle {
        id: pill

        x: face.sideX
        y: 124
        width: face.gridW
        height: 68
        radius: 34
        color: mt.pSurface
        border.width: 3
        border.color: mt.pLine
        antialiasing: true

        MaterialIcon {
            x: 24
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 30
        }

        Text {
            x: 70
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: "Search apps"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 24
            font.weight: Font.Bold
        }

        TextInput {
            id: input

            x: 70
            width: parent.width - 70 - 64
            anchors.verticalCenter: parent.verticalCenter
            color: mt.pInk
            selectionColor: mt.accentCyan
            selectedTextColor: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 24
            font.weight: Font.Bold
            clip: true
            focus: true
            selectByMouse: true

                  Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                    face.jumpRequested(event.key - Qt.Key_0)
                } else if ((event.modifiers & Qt.ControlModifier)
                    && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)
                    && extrasLayer.cycleCardTab(event.key === Qt.Key_Left ? -1 : 1)) {
                    // Ctrl+Left / Ctrl+Right on the emoji card: the call in the
                    // condition does the work. Any other mode falls through.
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P
                        && extrasLayer.pinKey()) {
                    // Ctrl+P on the clipboard card: pin / unpin the picked entry.
                    } else if (event.key === Qt.Key_Escape) {
                        face.back()
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (!extrasLayer.enter((event.modifiers & Qt.ShiftModifier) !== 0))
                            face.activateCurrent()
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                        || event.key === Qt.Key_Left && (input.text.length === 0 || extrasLayer.cardMode === "emoji")
                        || event.key === Qt.Key_Right && (input.text.length === 0 || extrasLayer.cardMode === "emoji")
                    ) {
                        face.moveKey(event.key)
                    } else if (event.key === Qt.Key_Tab) {
                        // Tab picks the next search engine on the web card.
                        if (!extrasLayer.tab(1))
                            face.moveKey(Qt.Key_Right)
                    } else if (event.key === Qt.Key_Backtab) {
                        if (!extrasLayer.tab(-1))
                            face.moveKey(Qt.Key_Left)
                    } else {
                        return
                    }
                    event.accepted = true
            }
        }

        // Clears what was typed.
        Item {
            visible: input.text.length > 0
            x: parent.width - 56
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 40

            Rectangle {
                anchors.fill: parent
                radius: 20
                color: clearArea.containsMouse ? mt.accentMint : "transparent"
            }

            MaterialIcon {
                anchors.centerIn: parent
                name: "close"
                size: 26
            }

            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.text = ""
                    face.focusSearch()
                }
            }
        }
    }

    // ===== the page =====
    // The area under the pill, down to near the bottom of what shows.
    readonly property real pageY: 228
    // Down to 1040 + 60 on the whole face, higher when less of it shows (34 = a
    // little room above the monitor's edge).
    readonly property real pageBottom: Math.max(pageY + 168 + 52, Math.min(1040, face.visibleBottom - 84 - 34)) + 60
    readonly property real pageH: pageBottom - pageY
    // The apps grid alone goes further down than the page (the cards of the extras
    // keep the page's size): to the monitor's edge, never past the glass.
    readonly property real gridBottom: Math.max(pageBottom, Math.min(1100, face.visibleReach))
    readonly property real gridH: gridBottom - pageY

    // APPS
    Item {
        id: drawerPage

        x: face.sideX
        // Under the rows (system actions, a command) when there are any, and out of
        // the way while a card (calculator, emoji...) has the page.
        y: face.pageY + extrasLayer.rowsHeight + (1 - face.revealT) * 30
        width: face.gridW
        height: face.gridH - extrasLayer.rowsHeight
        // The grid gives way to a card (calculator, clipboard...) by fading, as the card
        // fades in (LauncherExtras `cardK`); it used to be hidden in the same frame.
        opacity: face.revealT * (1 - extrasLayer.cardK)
        scale: (0.96 + 0.04 * face.revealT) * (1 - 0.025 * extrasLayer.cardK)
        transformOrigin: Item.Top
        visible: opacity > 0.01
        // Behind a card (or fading behind one) it takes no clicks.
        enabled: extrasLayer.cardK < 0.5

             WheelScroll {
            id: drawerWheel

            scroller: drawerGrid
            step: 60
            pixelFactor: 6.5
            smooth: true
        }

        GridView {
            id: drawerGrid

            anchors.fill: parent
            cellWidth: face.cellW
            cellHeight: face.cellH
            clip: true
            model: drawerModel
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: face.cellH * 3
            reuseItems: true
            pixelAligned: true
            delegate: tileDelegate
            // The keyboard's cursor: ONE plate under the delegates that slides from tile
            // to tile, so each arrow press shows where the pick went. Hover does not
            // bring it (a hovered icon only grows), so mouse and keys never both look
            // picked.
            highlight: pickPlate
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 90
            bottomMargin: Math.max(0, face.gridBottom - face.visibleBottom + 24)

            SekaiScrollBar {}
        }

        Text {
            id: noMatch

            anchors.centerIn: parent
            visible: face.searching && drawerGrid.count === 0 && extrasLayer.rows.length === 0
            text: "No apps match"
            color: face.lcdOn ? "#ffffff" : mt.pInkSub
            style: face.lcdOn ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0.10, 0.10, 0.22, 0.85)
            font.family: mt.fontFamily
            font.pixelSize: 24
            font.weight: Font.Bold
        }
    }

    // ===== the extras: cards and rows (LauncherExtras.qml) =====
    LauncherExtras {
        id: extrasLayer

        x: face.sideX
        y: face.pageY
        width: face.gridW
        height: face.pageH
        // Also while a card is still fading out after the text was cleared.
        visible: face.searching || extrasLayer.shownMode !== "" || extrasLayer.rowsHold.length > 0
        query: face.query
        // The data side (clipboard history...) runs while the screen is up, and starts as
        // soon as it is asked for, a beat before the slide shows it (the phone waits for
        // frames to be drawn before it moves, QuickPanel.armPrep), so a card is already
        // built when the slide begins. It used to wait for the screen to be visible, which
        // built it in the first frames of the slide.
        active: face.enabled
        // On show, including on its way in and out: the card stays built while it fades.
        present: face.visible
        appCount: face.drawerEntries.length
        pageWidth: face.gridW
        pageHeight: face.pageH

        onDoneRequested: face.doneRequested()
        onSetTextRequested: text => face.setText(text)
        onPickerRequested: face.pickerRequested()
        onColorPicked: hex => face.colorPickedBack(hex)
    }

    // ===== the keyboard's cursor =====
    // The same language as the extras' picked rows (LauncherExtras.qml): mint, a thick
    // outline and the phone's hard shadow, so a pick reads the same in a row and in
    // the grid, over the plain screen and over the wallpaper.
    Component {
        id: pickPlate

        Item {
            width: face.cellW
            height: face.cellH
            visible: face.gridPickShown

            Rectangle {
                x: 10
                y: 8
                width: parent.width - 16
                height: parent.height - 12
                radius: 26
                color: mt.pLineShadow
                antialiasing: true
            }

            Rectangle {
                x: 6
                y: 4
                width: parent.width - 16
                height: parent.height - 12
                radius: 26
                color: mt.accentMint
                border.width: 4
                border.color: mt.pLine
                antialiasing: true
            }
        }
    }

    // ===== one tile: the app's icon with the name under it =====
    // No button any more: no white cap, outline, ring, shadow or mint-to-cyan lit look,
    // and no chip behind the name. Just the icon and the name straight on the screen.
    // Pointer over it (or the arrow keys have it) the icon grows a little; pressed, it
    // shrinks and springs back. ONE animation each for lit and for pressed.
    Component {
        id: tileDelegate

        Item {
            id: tile

            required property var modelData
            required property int index

            readonly property bool picked: face.gridPickShown && GridView.isCurrentItem
            readonly property bool lit: (area.containsMouse && !drawerWheel.gliding && !drawerGrid.moving) || picked

            // 0 = the resting look, 1 = the lit look; glides between them. Every frame
            // of it redraws the whole phone, so it is short.
            property real litP: lit ? 1 : 0
            Behavior on litP {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            // 0 = up, 1 = pressed. Presses in fast, springs back past rest and settles.
            property real pressP: area.pressed ? 1 : 0
            Behavior on pressP {
                NumberAnimation {
                    duration: area.pressed ? 80 : 260
                    easing.type: area.pressed ? Easing.OutQuad : Easing.OutBack
                    easing.overshoot: area.pressed ? 0 : 2.2
                }
            }

            readonly property real iconBox: 100
            readonly property real iconY: 12

            width: face.cellW
            height: face.cellH

            // The path is looked up once per icon (AppSource.iconFor), not on
            // every tile that is built. Empty = the app has no icon (or the theme has
            // none by that name): the placeholder below stands in for it.
            readonly property string iconPath: face.source ? face.source.iconFor(tile.modelData.icon) : ""
            readonly property bool noIcon: tile.iconPath === "" || appIcon.status === Image.Error

            IconImage {
                id: appIcon

                x: Math.round((tile.width - implicitWidth) / 2)
                y: tile.iconY + Math.round((tile.iconBox - implicitHeight) / 2)
                implicitSize: 72
                asynchronous: true
                visible: !tile.noIcon
                transformOrigin: Item.Center
                scale: (1 + 0.10 * tile.litP) * (1 - 0.08 * tile.pressP)
                source: tile.iconPath
            }

            // An app with no icon: a coloured key with its first letter (AppPlaceholder.qml),
            // lit and pressed like a real icon.
            Loader {
                active: tile.noIcon
                x: Math.round((tile.width - 72) / 2)
                y: tile.iconY + Math.round((tile.iconBox - 72) / 2)
                width: 72
                height: 72
                transformOrigin: Item.Center
                scale: (1 + 0.10 * tile.litP) * (1 - 0.08 * tile.pressP)
                sourceComponent: AppPlaceholder {
                    size: 72
                    name: tile.modelData.name
                }
            }

            Text {
                id: nameText

                x: 4
                y: tile.iconY + tile.iconBox + 14
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
                // Up to two lines (long names wrapped at a space, or anywhere when there is
                // none), cut with "..." after that. A name that fits on one line sits exactly
                // where it did. Two lines of this size end inside the cell (168 px tall).
                wrapMode: Text.Wrap
                maximumLineCount: 2
                lineHeight: 0.88
                lineHeightMode: Text.ProportionalHeight
                elide: Text.ElideRight
                text: tile.modelData.name
                // Over the wallpaper there is no chip to read on any more, so the name
                // goes white with a thin dark edge; on the plain screen it is the usual ink.
                // On the cursor plate it is the dark ink the mint keys use, wallpaper or not.
                color: tile.picked ? mt.colBorder : (face.lcdOn ? "#ffffff" : mt.pInk)
                style: face.lcdOn && !tile.picked ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0.10, 0.10, 0.22, 0.85)
                font.family: mt.fontFamily
                font.pixelSize: 18
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }

            // The whole cell is the click target.
            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: face.keyNav = false
                onClicked: face.activate(tile.modelData)
            }
        }
    }
}
