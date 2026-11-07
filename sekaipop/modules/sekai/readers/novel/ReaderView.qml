// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

Item {
    id: readerView

    // The chrome speaks the shell's font; the chapter itself is set in a book face.
    readonly property string fontDisplay: Theme.fontFamily
    readonly property string readFont: "Noto Serif"
    readonly property string fontBody:    Theme.fontFamily

    signal backRequested()
    signal toggleFullscreen()

    property bool isFullscreen: false
    property real fontSize:      17
    property real lineHeight:    1.75
    property bool headerVisible: true

    function reset() {
        headerVisible = true
        textScroll.contentY = 0
    }

    readonly property bool _hasPrev: Novel.hasPrevChapter
    readonly property bool _hasNext: Novel.hasNextChapter

    Rectangle { anchors.fill: parent; color: Colors.page }

    // ── Reader bar ───────────────────────────────────────────────────────────
    ReaderBar {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
        z: 10
        shown: readerView.headerVisible

        RowLayout {
            anchors { fill: parent; leftMargin: 7; rightMargin: 10 }
            spacing: 6

            ReaderKey {
                icon: "arrow_back"
                onClicked: { Novel.clearChapter(); readerView.backRequested() }
            }

            Column {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 1

                Text {
                    width: parent.width
                    text: Novel.currentNovel ? Novel.currentNovel.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 10
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.inkSub; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: Novel.currentChapter ? Novel.currentChapter.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 13
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.ink; elide: Text.ElideRight
                }
            }

            ReaderBadge {
                visible: Novel.currentChapter !== null && Novel.currentChapter.wordCount > 0
                rotation: 0
                fill: Theme.accentCyan
                text: Novel.currentChapter !== null
                    ? ((Math.round(Novel.currentChapter.wordCount / 100) / 10) + "k words").toUpperCase() : ""
            }

            ReaderKey {
                label: "A−"
                onClicked: readerView.fontSize = Math.max(13, readerView.fontSize - 1)
            }

            ReaderKey {
                label: "A+"
                onClicked: readerView.fontSize = Math.min(26, readerView.fontSize + 1)
            }

            ReaderKey {
                icon: readerView.isFullscreen ? "fullscreen_exit" : "fullscreen"
                lit: readerView.isFullscreen
                onClicked: readerView.toggleFullscreen()
            }
        }
    }

    // Loading: a ghost page in the reader's own measure and type size
    Rectangle {
        anchors.fill: parent; color: Colors.page; z: 8
        opacity: Novel.isFetchingChapter ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        SkeletonText {
            anchors.fill: parent
            active: Novel.isFetchingChapter
            fontSize: readerView.fontSize
            lineHeight: readerView.lineHeight
            topInset: readerView.headerVisible ? 72 : 2
        }
    }

    LoadingBar {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        z: 10
        active: Novel.isFetchingChapter
    }

    Rectangle {
        anchors.fill: parent; color: Colors.page; z: 7
        visible: Novel.chapterError.length > 0 && !Novel.isFetchingChapter
        Column {
            anchors.centerIn: parent; spacing: 10
            Text {
                text: "⚠"; font.pixelSize: 32; color: Colors.error; opacity: 0.85
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: Novel.chapterError; color: Qt.rgba(1,1,1,0.4)
                font.pixelSize: 11; font.family: readerView.fontBody
                wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
            }
        }
    }

    Flickable {
        id: textScroll
        anchors {
            fill: parent
            topMargin: readerView.headerVisible ? 72 : 2
            bottomMargin: 72
        }
        contentWidth: width
        contentHeight: textColumn.implicitHeight + 80
        clip: true; boundsBehavior: Flickable.StopAtBounds
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent; propagateComposedEvents: true
            onClicked: { readerView.headerVisible = !readerView.headerVisible; mouse.accepted = false }
        }

        Column {
            id: textColumn
            width: Math.min(parent.width - 48, 720)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 36; bottomPadding: 48; spacing: 0

            StyledText {
                width: parent.width
                text: Novel.currentChapter ? Novel.currentChapter.title : ""
                font.family: readerView.readFont
                font.pixelSize: readerView.fontSize + 7
                font.bold: true
                color: Qt.rgba(0.96, 0.93, 0.87, 0.90)
                wrapMode: Text.Wrap; lineHeight: 1.25; bottomPadding: 8
            }

            Item {
                width: parent.width; height: 24
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    Rectangle { width: 8;  height: 2; radius: 1; color: Colors.primary; opacity: 0.3 }
                    Rectangle { width: 32; height: 2; radius: 1; color: Colors.primary; opacity: 0.7 }
                    Rectangle { width: 8;  height: 2; radius: 1; color: Colors.primary; opacity: 0.3 }
                }
            }

            Item { width: 1; height: 20 }

            Repeater {
                model: Novel.currentChapter ? Novel.currentChapter.paragraphs : []
                StyledText {
                    width: textColumn.width
                    text: modelData
                    font.family: readerView.readFont
                    font.pixelSize: readerView.fontSize
                    color: Qt.rgba(0.91, 0.87, 0.80, 0.87)
                    wrapMode: Text.Wrap; lineHeight: readerView.lineHeight
                    bottomPadding: Math.round(readerView.fontSize * readerView.lineHeight * 0.75)
                    textFormat: Text.PlainText
                }
            }
        }

        ScrollBar.vertical: StyledScrollBar {
            thickness: 4
            handleRadius: 2
            handleOpacity: 0.6
        }
    }

    // ── Chapter navigation ───────────────────────────────────────────────────
    ReaderBar {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }
        z: 10
        atBottom: true

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 12

            ReaderChip {
                icon: "chevron_left"
                text: "Prev"
                enabled: readerView._hasPrev
                onClicked: { Novel.fetchPrevChapter(); textScroll.contentY = 0 }
            }

            // How far down the chapter
            ReaderProgress {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                value: textScroll.contentHeight > textScroll.height
                    ? Math.min(1, (textScroll.contentY + textScroll.height) / textScroll.contentHeight)
                    : 1
            }

            ReaderChip {
                icon: "chevron_right"
                text: "Next"
                lit: readerView._hasNext
                enabled: readerView._hasNext
                onClicked: { Novel.fetchNextChapter(); textScroll.contentY = 0 }
            }
        }
    }
}
