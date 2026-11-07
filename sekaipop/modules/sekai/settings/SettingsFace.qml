import QtQuick
import Quickshell
import QtQuick.Effects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.phone
import qs.modules.sekai.quickPanel

// The screen of the Settings phone: what is drawn inside the landscape
// PhoneBody. Like QuickPanelFace.qml it is pure UI: QuickPanel.qml (through
// SettingsStage.qml) gives it what the shell knows and turns its signals into
// actions.
//
// The layout is a game's main menu, held sideways, with a page behind each
// button. There is no list of pages beside the page; the menu IS the list:
//
//   MENU     (camera)  <leaning title banner>                 clock   <x>
//            (cut-out)  ╱ 01 Quick ╱  ╱ 02 General ╱  ╱ 03 Bar ╱  ╱ 04 Desktop ╱
//                                  ╱ 05 Hyprland ╱  ╱ 06 About ╱
//
//   A PAGE   (camera)  <leaning title banner>        [Menu]  clock   <x>
//            (cut-out) ┌────────────────────────────────────────────────┐
//                      │  the page, the whole width: a scrolling stack  │
//                      │  of cards, each with a coloured name plate     │
//                      └────────────────────────────────────────────────┘
//
// It opens on the menu: six big leaning tiles, the second row pushed a
// little to the right. Pick one and the menu shrinks away while the page
// fades in. While a page is open the header carries a "Menu" key that goes
// back to the tiles. Behind it all is SekaiBackdrop: a pale
// wash with halftones, diagonal bands and stars, so the cards sit on
// something.
//
// The camera cut-out is on the left edge, so everything that sits beside
// it keeps `safeLeft` clear (what a real phone's "safe area" does).
Item {
    id: face

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
    readonly property bool classicPanel: true

    width: 1440
    height: 760

    // ===== data, given by SettingsStage.qml =====
    property var source: null
    property var notificationSource: null
    // The monitor the panel is on, for the per-monitor shell size.
    property string screenName: ""
    property string clockText: "00:00AM"
    property string dateText: "Sun, 20  Sep"

    // What the phone around this screen looks like, given by SettingsStage.qml.
    // The backdrop is drawn only inside the glass (inset from the rim and
    // bezel, with the screen's own round corners), so the phone's frame, its
    // corners and the camera cut-out stay visible around it.
    property real screenInset: 26
    property real cornerRadius: 92
    property real renderScale: 1

    // ===== what it asks for =====
    signal closeRequested()
    signal wallpapersRequested()
    // The picker, on its Lockscreen tab (Separate Lockscreen Wallpaper).
    signal lockWallpapersRequested()
    signal desktopEditRequested()
    // The keybinds panel (Settings > Hyprland > Keybinds): the phone goes away, the panel comes up.
    signal keybindsRequested()
    // The search field is done with the keyboard (give it back to the panel).
    signal searchLeft()

    // ===== pages =====
    readonly property var pages: [
        { id: "quick", icon: "instant_mix", label: "Quick", title: "Quick", sub: "The things you reach for most" },
        { id: "general", icon: "tune", label: "General", title: "General", sub: "How the shell behaves" },
        { id: "bar", icon: "toast", label: "Bar", title: "Bar", sub: "Where it sits and what it carries" },
        { id: "desktop", icon: "desktop_windows", label: "Desktop", title: "Desktop", sub: "Wallpaper, widgets and effects" },
        { id: "hyprland", icon: "grid_view", label: "Hyprland", title: "Hyprland", sub: "Windows, workspaces and input" },
        { id: "about", icon: "info", label: "About", longLabel: "About / Update", title: "About / Update", sub: "Version, updates and credits" }
    ]

    property int pageIndex: 0

    // true = the menu of six tiles is showing, false = a page is.
    property bool hub: true
    // 1 = the menu is fully there, 0 = a page is. Glides between the two.
    property real hubP: hub ? 1 : 0
    Behavior on hubP {
        NumberAnimation {
            duration: 340
            easing.type: Easing.OutCubic
        }
    }

    // The page position the carousel is at, which glides to pageIndex (but
    // jumps straight there when it comes up from the menu, so you don't see
    // the page you last had sliding away).
    property real pos: pageIndex
    Behavior on pos {
        enabled: !face.hub
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }
    }

    // Pages are built the first time they're shown (then kept, so scroll
    // positions survive) and the rest are warmed up in the background.
    property var visited: [true, false, false, false, false, false]

    function visit(i) {
        if (visited[i])
            return
        const v = visited.slice()
        v[i] = true
        visited = v
    }

    // Open page i (from the menu or from another page).
    function go(i) {
        pageIndex = Math.max(0, Math.min(pages.length - 1, i))
        hub = false
    }

    // Back to the menu.
    function showHub() {
        hub = true
    }

    // Next / previous page. Does nothing on the menu.
    function step(d) {
        if (hub)
            return
        go(pageIndex + d)
    }

    onPageIndexChanged: {
        visit(pageIndex)
        swap.restart()
        face.remember()
    }

    onHubChanged: {
        swap.restart()
        face.remember()
    }

    function remember() {
        SettingsService.set("settings.page", hub ? "" : pages[pageIndex].id)
    }

    function restorePage() {
        const i = pages.findIndex(p => p.id === SettingsService.get("settings.page"))
        if (i >= 0)
            go(i)
    }

    Component.onCompleted: {
        if (SettingsService.loaded)
            face.restorePage()
    }

    Connections {
        target: SettingsService
        function onLoadedChanged() {
            if (SettingsService.loaded)
                face.restorePage()
        }
    }

    // Only counts while the panel is on screen.
    property bool active: true

    // Every page that has been built goes back to its top when the Settings
    // come up (the pages themselves are kept, so this is what resets them).
    function scrollPagesToTop() {
        for (let i = 0; i < pageRepeater.count; i++) {
            const slot = pageRepeater.itemAt(i)
            if (slot && slot.item && slot.item.scrollToTop)
                slot.item.scrollToTop()
        }
    }

    onActiveChanged: {
        if (active && hub)
            face.scrollPagesToTop()
        if (!active)
            search.clear()
    }

    // False while the phone is still turning in / out or ringing out
    // (SettingsStage hands it down). The pages that have not been built yet are
    // warmed up one by one on the timer below, and building a page is a few
    // hundred items on the one thread that also drives the turn: done DURING the
    // turn, those builds were stalls in the middle of the animation. They wait
    // until the phone has landed instead (and are built incrementally between
    // frames, see the Loader below). Defaults to true, so nothing else changes.
    property bool calm: true

    Timer {
        interval: 280
        repeat: true
        running: face.active && face.calm
        onTriggered: {
            for (let i = 0; i < face.pages.length; i++) {
                if (!face.visited[i]) {
                    face.visit(i)
                    return
                }
            }
            running = false
        }
    }

    // ===== layout numbers =====
    readonly property real safeLeft: 96
    readonly property real safeRight: 50

    // Pages use the whole width.
    readonly property real pageX: safeLeft
    readonly property real pageTop: 114
    readonly property real pageWidth: width - safeLeft - safeRight
    readonly property real pageHeight: 594

    // The menu: two rows, the first one the longer (seven pages: four over three),
    // the second pushed right. With an odd count it sits half a tile in, like
    // bricks; with an even one, a small step.
    readonly property real hubGapX: 26
    readonly property real hubGapY: 30
    readonly property int hubCols: Math.ceil(pages.length / 2)
    readonly property real hubTileW: Math.floor((pageWidth - (pages.length % 2 ? 0 : 34) - (hubCols - 1) * hubGapX - 10) / hubCols)
    readonly property real hubStagger: pages.length % 2 ? Math.floor((hubTileW + hubGapX) / 2) : 34
    readonly property real hubTileH: Math.floor((pageHeight - hubGapY - 16) / 2)

    // What the cards sit on (SettingsPage uses it for its fades).
    readonly property color backdropColor: backdrop.color

    // The backdrop lives inside a screen-shaped window. It is laid out in the
    // face's own coordinates (so the stars and bands sit where they were
    // drawn) and then cropped to the glass with a rounded mask.
    Item {
        id: screenArea

        x: face.screenInset
        y: face.screenInset
        width: face.width - 2 * face.screenInset
        height: face.height - 2 * face.screenInset
        z: -10

        layer.enabled: true
        layer.smooth: true
        // At the density the face itself is drawn at (twice the screen's, like
        // screenMask below). Left at its default the backdrop is one texel per
        // design unit and gets blown up soft when it lands on the phone.
        layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                   Math.ceil(height * face.renderScale * 2))
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: screenMask
        }

        SekaiBackdrop {
            id: backdrop
            x: -face.screenInset
            y: -face.screenInset
            width: face.width
            height: face.height
        }
    }

    Item {
        id: screenMask
        width: screenArea.width
        height: screenArea.height
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                   Math.ceil(height * face.renderScale * 2))

        Rectangle {
            anchors.fill: parent
            color: "black"
            radius: Math.max(0, face.cornerRadius - face.screenInset)
            antialiasing: true
        }
    }

    // ===== header =====
    property int shownPage: -1

    readonly property var hubInfo: ({ icon: "settings", title: "Settings", sub: "Pick what you want to change" })
    readonly property var shownInfo: shownPage < 0 ? hubInfo : pages[shownPage]

    SequentialAnimation {
        id: swap
        NumberAnimation {
            target: titleBlock
            property: "opacity"
            to: 0
            duration: 80
        }
        ScriptAction { script: face.shownPage = face.hub ? -1 : face.pageIndex }
        NumberAnimation {
            target: titleBlock
            property: "opacity"
            to: 1
            duration: 200
        }
    }

    // The title banner: a lit leaning plate, as long as its words.
    Item {
        id: banner

        x: face.safeLeft - 8
        y: 28
        height: 70
        width: bannerKey.capW + 8

        SekaiKey {
            id: bannerKey

            capW: Math.max(420, 92 + Math.max(titleText.implicitWidth, subText.implicitWidth) + 120)
            capH: 66
            skew: 0.26 * mt.settingsLean
            radius: 26
            lit: true
            litP: 1
            borderBase: 4
            borderLit: 4
            ringExtra: 5
            shadowBaseX: 5
            shadowBaseY: 4
            flatShadow: mt.quickFlat

            Behavior on capW {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Item {
                id: titleBlock
                anchors.fill: parent

                Rectangle {
                    x: 54 - width / 2
                    y: (bannerKey.capH - height) / 2
                    width: 34
                    height: 34
                    radius: 10
                    rotation: 45
                    color: mt.colBg
                    border.width: 3
                    border.color: mt.colBorder
                    antialiasing: true
                }

                MaterialIcon {
                    x: 54 - width / 2
                    y: (bannerKey.capH - height) / 2
                    size: 24
                    name: face.shownInfo.icon
                    weight: mt.settingsIconWeight
                    // Outline like every other icon (Theme.iconFill); this one
                    // used to be forced solid, which turned the gear into a blob.
                    color: mt.colBorder
                }

                Column {
                    x: 92
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: titleText
                        text: face.shownInfo.title
                        color: mt.colBorder
                        font.family: mt.fontFamily
                        // The lit band inside the plate is 48 px tall (66 - 2 * (4 + 5));
                        // 26 + 15 = 41 px of text leaves it centred with ~3 px each side
                        // (it was 29 + 17 = 46: touching both edges).
                        font.pixelSize: 25
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                        lineHeight: 26
                        lineHeightMode: Text.FixedHeight
                    }

                    Text {
                        id: subText
                        text: face.shownInfo.headerSub !== undefined ? face.shownInfo.headerSub : face.shownInfo.sub
                        color: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.78)
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        lineHeight: 15
                        lineHeightMode: Text.FixedHeight
                    }
                }
            }

            // a star at the far end of the plate
            MaterialIcon {
                x: bannerKey.capW - 52
                y: 8
                size: 24
                name: "star"
                weight: mt.settingsIconWeight
                rotation: 14
                color: mt.colBg
            }
        }
    }

    // Clock + date in a leaning chip, beside the close button: the status
    // line of the phone.
    SekaiKey {
        id: clockChip

        x: closeButton.x - 16 - capW - 6
        y: 34
        capW: Math.max(clockLabel.implicitWidth, dateLabel.implicitWidth) + 62
        capH: 56
        skew: 0.26 * mt.settingsLean
        radius: 20
        flatShadow: mt.quickFlat

        Column {
            anchors.centerIn: parent

            Text {
                id: clockLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.clockText
                color: mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 21
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
                lineHeight: 24
                lineHeightMode: Text.FixedHeight
            }

            Text {
                id: dateLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.dateText
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                lineHeight: 16
                lineHeightMode: Text.FixedHeight
            }
        }
    }

    SettingRoundButton {
        id: closeButton
        x: face.width - face.safeRight - width
        y: 33
        size: 58
        icon: "close"
        onClicked: face.closeRequested()
    }

    // ===== back to the menu =====
    SekaiNavKey {
        id: menuKey

        x: clockChip.x - 24 - width
        y: 38
        icon: "apps"
        label: "Menu"
        opacity: 1 - face.hubP
        visible: opacity > 0.01
        enabled: !face.hub
        onClicked: face.showHub()
    }

    // ===== search =====
    property string searchText: ""
    property var results: []
    property int selected: 0
    readonly property bool searching: searchText.trim() !== ""

    onSearchTextChanged: {
        if (searching) {
            for (let i = 0; i < pages.length; i++)
                visit(i)
        }
        searchTimer.restart()
    }

    Timer {
        id: searchTimer
        interval: 120
        onTriggered: face.rebuildResults()
    }

    function indexItems(node, pageIdx, card, out) {
        const kids = node.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            const cardTitle = c.isSectionCard === true ? String(c.title) : card
            if (typeof c.label === "string" && c.label !== "" && c.selected === undefined) {
                out.push({
                    item: c,
                    page: pageIdx,
                    card: cardTitle,
                    label: c.label,
                    icon: typeof c.icon === "string" ? c.icon : "",
                    hay: (c.label + " " + (typeof c.detail === "string" ? c.detail : "") + " "
                        + cardTitle + " " + pages[pageIdx].label).toLowerCase()
                })
            } else if (c.children && c.children.length > 0) {
                indexItems(c, pageIdx, cardTitle, out)
            }
        }
    }

    function rebuildResults() {
        const q = searchText.trim().toLowerCase()
        if (q === "") {
            results = []
            return
        }
        const words = q.split(/\s+/)
        const out = []
        for (let i = 0; i < pageRepeater.count; i++) {
            const slot = pageRepeater.itemAt(i)
            if (!slot || !slot.item || !slot.item.cards)
                continue
            const all = []
            indexItems(slot.item.cards, i, "", all)
            for (const r of all) {
                if (words.every(w => r.hay.indexOf(w) >= 0))
                    out.push(r)
            }
        }
        results = out
    }

    onResultsChanged: selected = 0

    function stepResult(d) {
        if (results.length === 0)
            return
        selected = Math.max(0, Math.min(results.length - 1, selected + d))
        const top = 18 + selected * 82
        if (top < resultsFlick.contentY)
            resultsFlick.contentY = top - 18
        else if (top + 68 > resultsFlick.contentY + resultsFlick.height)
            resultsFlick.contentY = top + 68 + 18 - resultsFlick.height
    }

    function openResult(r) {
        const slot = pageRepeater.itemAt(r.page)
        search.clear()
        go(r.page)
        searchLeft()
        Qt.callLater(() => {
            if (slot && slot.item)
                slot.item.scrollToItem(r.item)
        })
    }

    function typeIntoSearch(character) {
        search.begin(character)
    }

    SearchPill {
        id: search
        x: menuKey.x - 24 - width
        y: 36
        width: 280
        height: 52
        placeholder: "Search settings"
        stepKeys: true
        onTextChanged: face.searchText = text
        onStepped: direction => face.stepResult(direction)
        onLeave: {
            if (face.results.length > 0)
                face.openResult(face.results[Math.min(face.selected, face.results.length - 1)])
            else
                face.searchLeft()
        }
    }

    Keys.onEscapePressed: {
        search.clear()
        face.searchLeft()
    }

    // ===== the menu =====
    Item {
        id: hubArea

        x: face.pageX
        y: face.pageTop
        width: face.pageWidth
        height: face.pageHeight
        opacity: face.hubP
        scale: 0.96 + 0.04 * face.hubP
        visible: opacity > 0.01
        enabled: face.hub

        Repeater {
            model: face.pages

            delegate: SekaiHubTile {
                required property var modelData
                required property int index

                readonly property int col: index % face.hubCols
                readonly property int row: Math.floor(index / face.hubCols)

                x: col * (face.hubTileW + face.hubGapX) + row * face.hubStagger
                y: 4 + row * (face.hubTileH + face.hubGapY)
                tileW: face.hubTileW
                tileH: face.hubTileH
                slot: index
                number: index + 1
                icon: modelData.icon
                label: modelData.longLabel !== undefined ? modelData.longLabel : modelData.label
                subtitle: modelData.sub
                badge: modelData.id === "about" && ((UpdateService.status === "behind" && !UpdateService.unknown) || UpdateService.systemNeeded)
                onClicked: face.go(index)
            }
        }
    }

    // ===== the pages =====
    Item {
        id: pageArea
        x: face.pageX
        // 12 higher than the menu's top, so the jump chips fit under the
        // banner; a page without chips pushes its cards back down by the same
        // 12 (SettingsPage.topGap), so they sit where they always did.
        y: face.pageTop - 12
        width: face.pageWidth
        height: face.pageHeight + 12
        clip: true
        opacity: 1 - face.hubP
        visible: opacity > 0.01
        enabled: !face.hub

        Repeater {
            id: pageRepeater
            model: face.pages

            delegate: Loader {
                id: slot

                required property var modelData
                required property int index

                readonly property real d: slot.index - face.pos

                width: pageArea.width
                height: pageArea.height
                // Pages beside the current one slide in sideways while they
                // fade, a little smaller when away.
                x: d * 90
                opacity: Math.max(0, 1 - Math.abs(d) * 1.7)
                scale: 1 - Math.min(1, Math.abs(d)) * 0.03
                visible: opacity > 0.01
                enabled: slot.index === face.pageIndex
                active: face.visited[slot.index] === true
                // A page that is only being warmed up in the background is built
                // a slice at a time between frames, so it never stalls anything.
                // The page you just asked for (pageIndex has already moved to it
                // when it becomes active) is built at once, as before.
                asynchronous: slot.index !== face.pageIndex
                onLoaded: {
                    if (face.searching)
                        searchTimer.restart()
                }
                sourceComponent: slot.index === 0 ? quickPage
                    : slot.index === 1 ? generalPage
                    : slot.index === 2 ? barPage
                    : slot.index === 3 ? desktopPage
                    : slot.index === 4 ? hyprlandPage : aboutPage
            }
        }
    }

    // The search results: one row per setting that matches, over the pages.
    Item {
        id: searchArea
        x: face.pageX
        y: face.pageTop - 12
        width: face.pageWidth
        height: face.pageHeight + 12
        clip: true
        opacity: face.searching ? 1 : 0
        visible: opacity > 0.01
        enabled: face.searching

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Rectangle {
            anchors.fill: parent
            color: face.backdropColor
        }

        Text {
            visible: face.results.length === 0
            anchors.centerIn: parent
            text: "No settings found"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }

        WheelScroll { scroller: resultsFlick }
        Flickable {
            id: resultsFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: resultsColumn.height + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: resultsColumn
                x: 4
                y: 18
                width: parent.width - 16
                spacing: 14

                Repeater {
                    model: face.results

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: resultsColumn.width
                        height: 68
                        radius: 20
                        color: row.index === face.selected ? mt.pSurfaceHover : mt.pSurface
                        border.width: 3
                        border.color: mt.pLine
                        antialiasing: true

                        MaterialIcon {
                            x: 26
                            anchors.verticalCenter: parent.verticalCenter
                            size: 28
                            name: row.modelData.icon !== "" ? row.modelData.icon : "settings"
                            weight: mt.settingsIconWeight
                            color: mt.pInk
                        }

                        Column {
                            x: 78
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: row.modelData.label
                                color: mt.pInk
                                font.family: mt.fontFamily
                                font.pixelSize: 20
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            Text {
                                text: face.pages[row.modelData.page].label + (row.modelData.card !== "" ? "  ·  " + row.modelData.card : "")
                                color: mt.pInkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: face.selected = row.index
                            onClicked: face.openResult(row.modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: quickPage
        SettingsPageQuick {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }

    Component {
        id: generalPage
        SettingsPageGeneral {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }

    Component {
        id: barPage
        SettingsPageBar {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }

    Component {
        id: desktopPage
        SettingsPageDesktop {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }

    Component {
        id: hyprlandPage
        SettingsPageHyprland {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }

    Component {
        id: aboutPage
        SettingsPageAbout {
            host: face
            width: pageArea.width
            height: pageArea.height
        }
    }
}
