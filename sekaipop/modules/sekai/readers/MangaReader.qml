import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import qs.modules.sekai.readers.manga

// The manga reader. By default it takes the whole screen (a full window); the size key beside
// minimize / close in the header (or the reader's own full-screen key) puts it back as a card on
// the left edge, and the choice is kept between sessions (MangaPrefs.fullWindow).
// The frame (card, header plate, tabs, pop-in and swallow) is ReaderPanel's; this holds the
// Browse / Library stacks.
ReaderPanel {
    id: root

    side: "left"
    // The side card's width (used when the full window is off): a little wider than the default
    // (600), the header holds the profile key and three big keys.
    panelWidth: 650
    title: "Tankobon"
    colorTop: Theme.accentMint
    colorBottom: Theme.accentCyan
    // Whole screen: always when `MangaPrefs.fullWindow` is on (the default), otherwise only while
    // a chapter is read (Tablet mode wants it).
    wide: MangaPrefs.fullWindow || root.fullscreen
    // A chapter is open (stack 2 of the tab in view): no Manga / Browse / Library / minimize
    // header, just the reader's own bar.
    hideHeader: root.tabIndex === 0 ? root.browseStack === 2 : root.libraryStack === 2

    readonly property string fontBody: Theme.fontFamily

    property bool fullscreen: false

    // ── Mouse cursor ─────────────────────────────────────────────────────────
    // While a chapter is on screen, Hyprland hides a cursor that rests for a couple of seconds
    // and shows it on the next move (scripts/hyprland/reader-cursor.sh). It is Hyprland's doing
    // because the reader cannot do it alone: an app's blank cursor only takes effect when the
    // pointer next moves. The setting is put back when the chapter, the panel or the reader goes
    // away. (It is Hyprland's global setting, so it also hides the cursor over other windows for
    // as long as a chapter is up.)
    readonly property string cursorScript: Directories.script("hyprland/reader-cursor.sh")
    readonly property bool cursorHides: root.open && !root.minimized && root.hideHeader
    property bool _cursorApplied: false

    onCursorHidesChanged: cursorTimer.restart()

    // Debounced: switching between the Browse and Library tabs turns one reader off and the
    // other on within the same moment, and only the end state should reach Hyprland.
    Timer {
        id: cursorTimer
        interval: 250
        onTriggered: {
            if (root.cursorHides === root._cursorApplied)
                return
            root._cursorApplied = root.cursorHides
            Quickshell.execDetached(["sh", root.cursorScript, root.cursorHides ? "on" : "off"])
        }
    }

    Component.onDestruction: {
        if (root._cursorApplied)
            Quickshell.execDetached(["sh", root.cursorScript, "off"])
    }

    // The reader's full-screen key: when the panel is already wide it gives the screen back (the
    // side card), otherwise a chapter takes the whole width for as long as it is read.
    function toggleWide() {
        if (root.wide) {
            root.fullscreen = false
            MangaPrefs.setFullWindow(false)
        } else {
            root.fullscreen = true
        }
    }

    property int browseStack: 0
    property int libraryStack: 0

    property string selectedMangaId: ""

    // The AniList account key, in the header by the Browse / Library switch: the logged-in
    // profile (avatar and name), or "Log in" while nobody is.
    headerData: AccountKey {
        onClicked: { sourcesPage.close(); anilistLogin.open() }
    }

    // The size key beside minimize / close: full window <-> the side card on the left edge
    // (kept between sessions).
    sizeKey: true
    sizeKeyFull: MangaPrefs.fullWindow
    onSizeKeyClicked: MangaPrefs.setFullWindow(!MangaPrefs.fullWindow)

    // The AniList page and the Sources page cover the body (not the header) while they are open
    onTabIndexChanged: {
        if (anilistLogin.visible) anilistLogin.close()
        if (sourcesPage.visible) sourcesPage.close()
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: root.tabIndex

        Item {

            BrowseView {
                anchors.fill: parent
                visible: root.browseStack === 0
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onSourcesRequested: sourcesPage.open()

                onMangaSelected: function(mangaId) {
                    root.selectedMangaId = mangaId
                    root.browseStack = 1
                }
            }

            DetailView {
                id: browseDetail
                anchors.fill: parent
                visible: root.browseStack === 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onBackRequested:   { root.browseStack = 0 }
                onChapterSelected: { root.browseStack = 2 }
            }

            ReaderView {
                id: browseReader
                anchors.fill: parent
                visible: root.browseStack === 2
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                isFullscreen: root.wide
                onToggleFullscreen: root.toggleWide()

                onBackRequested: {
                    root.browseStack = 1
                    root.fullscreen = false
                    browseReader.reset()
                }
            }
        }

        Item {
            LibraryView {
                anchors.fill: parent
                visible: root.libraryStack === 0
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onMangaSelected: function(mangaId) {
                    root.selectedMangaId = mangaId
                    root.libraryStack = 1
                }
                onLoginRequested: anilistLogin.open()
            }

            DetailView {
                id: libraryDetail
                anchors.fill: parent
                visible: root.libraryStack === 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onBackRequested:   { root.libraryStack = 0 }
                onChapterSelected: { root.libraryStack = 2 }
            }

            ReaderView {
                id: libraryReader
                anchors.fill: parent
                visible: root.libraryStack === 2
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                isFullscreen: root.wide
                onToggleFullscreen: root.toggleWide()

                onBackRequested: {
                    root.libraryStack = 1
                    root.fullscreen = false
                    libraryReader.reset()
                }
            }
        }
    }

    // Suwayomi's extensions, repositories and the sources Browse asks (the puzzle key beside
    // Source in Browse opens it)
    SourcesPage {
        id: sourcesPage
        anchors.fill: parent
        z: 20
    }

    AniListLogin {
        id: anilistLogin
        anchors.fill: parent
        z: 20

        // A cover on the profile page (a favourite, or Jump back in): the page closes and the
        // title opens in the tab that is showing.
        onMangaSelected: function(mangaId) {
            anilistLogin.close()
            root.selectedMangaId = mangaId
            if (root.tabIndex === 0) root.browseStack = 1
            else root.libraryStack = 1
        }
    }
}
