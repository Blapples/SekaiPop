import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.sekai.readers
import qs.modules.sekai.readers.novel

// The novel reader, a panel on the right edge. Like the manga reader it takes the whole screen
// by default (a full window); the size key beside minimize / close in the header (or the
// reader's own full-screen key) puts it back as a card on the right edge, and the choice is
// kept between sessions (NovelPrefs.fullWindow).
// The frame (card, header plate, tabs, pop-in and swallow) is ReaderPanel's; this holds the
// Browse / Library stacks.
ReaderPanel {
    id: root

    side: "right"
    title: "Novel"
    // The two accents the other way round, so the two plates can be told apart.
    colorTop: Theme.accentCyan
    colorBottom: Theme.accentMint
    // Whole screen: always when `NovelPrefs.fullWindow` is on (the default), otherwise only
    // while a chapter is read and the reader's full-screen key is on.
    wide: NovelPrefs.fullWindow || root.fullscreen
    // A chapter is open (stack 2 of the tab in view): no Novel / Browse / Library / minimize
    // header, just the reader's own bars.
    hideHeader: root.tabIndex === 0 ? root.browseStack === 2 : root.libraryStack === 2

    readonly property string fontBody: Theme.fontFamily

    property bool fullscreen: false

    // While a chapter is on screen a resting mouse cursor is hidden (see ReaderCursorHider).
    ReaderCursorHider {
        active: root.open && !root.minimized && root.hideHeader
    }

    // The reader's full-screen key: when the panel is already wide it gives the screen back (the
    // side card), otherwise a chapter takes the whole width for as long as it is read.
    function toggleWide() {
        if (root.wide) {
            root.fullscreen = false
            NovelPrefs.setFullWindow(false)
        } else {
            root.fullscreen = true
        }
    }

    // The size key beside minimize / close: full window <-> the side card on the right edge
    // (kept between sessions).
    sizeKey: true
    sizeKeyFull: NovelPrefs.fullWindow
    onSizeKeyClicked: NovelPrefs.setFullWindow(!NovelPrefs.fullWindow)

    property int browseStack: 0
    property int libraryStack: 0

    // The AniList account key, in the header by the Browse / Library switch: the logged-in
    // profile (avatar and name), or "Log in" while nobody is. Novels only; the login is the
    // manga reader's.
    headerData: AccountKey {
        onClicked: anilistSheet.open()
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

                onNovelSelected: function(novelId) {
                    root.browseStack = 1
                }
            }

            DetailView {
                id: browseDetail
                anchors.fill: parent
                visible: root.browseStack === 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onBackRequested:    { root.browseStack = 0 }
                onChapterSelected:  { root.browseStack = 2 }
                onLoginRequested:   anilistSheet.open()
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

                onNovelSelected: function(novelId) {
                    root.libraryStack = 1
                }
            }

            DetailView {
                id: libraryDetail
                anchors.fill: parent
                visible: root.libraryStack === 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                onBackRequested:   { root.libraryStack = 0 }
                onChapterSelected: { root.libraryStack = 2 }
                onLoginRequested:  anilistSheet.open()
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
                    libraryReader.reset()
                }
            }
        }
    }

    // The AniList page (log in / out, "update as I read") covers the body, not the header
    AniListSheet {
        id: anilistSheet
        anchors.fill: parent
        z: 20
    }
}
