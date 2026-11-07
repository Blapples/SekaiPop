import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.sekai.readers
import qs.modules.sekai.readers.novel

// The novel reader, a panel on the right edge. The frame (card, header plate, tabs, pop-in
// and swallow) is ReaderPanel's; this holds the Browse / Library stacks. While a chapter is
// being read it can take the whole screen width (`fullscreen`).
ReaderPanel {
    id: root

    side: "right"
    title: "Novel"
    // The two accents the other way round, so the two plates can be told apart.
    colorTop: Theme.accentCyan
    colorBottom: Theme.accentMint
    wide: root.fullscreen

    readonly property string fontBody: Theme.fontFamily

    property bool fullscreen: false

    property int browseStack: 0
    property int libraryStack: 0

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
            }

            ReaderView {
                id: browseReader
                anchors.fill: parent
                visible: root.browseStack === 2
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                isFullscreen: root.fullscreen
                onToggleFullscreen: root.fullscreen = !root.fullscreen

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
            }

            ReaderView {
                id: libraryReader
                anchors.fill: parent
                visible: root.libraryStack === 2
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                isFullscreen: root.fullscreen
                onToggleFullscreen: root.fullscreen = !root.fullscreen

                onBackRequested: {
                    root.libraryStack = 1
                    libraryReader.reset()
                }
            }
        }
    }
}
