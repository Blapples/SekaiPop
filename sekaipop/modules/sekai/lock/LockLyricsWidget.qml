import QtQuick

// The line of the song being sung, and the next one under it, in a capsule of its own (it used
// to be part of the Now playing widget, LockMediaWidget.qml). It is LockLyrics.qml, the same
// capsule the Gacha look has, so the words, the timing and the sync nudge are the ones the
// desktop Lyrics widget uses.
//
// Putting this widget on the lockscreen is what switches it on: it does not wait for
// Settings -> General -> Lockscreen -> Lyrics (that one is for the Gacha look). It asks the
// lyrics providers for the song, once per track and only while a player is running, and
// nothing runs without one. It is drawn only while there are words to show: the capsule
// opens when a line starts and closes when there are none. In the editor it shows a sample
// line, so there is something to grab.
LockWidget {
    id: root

    readonly property bool present: root.media !== null && root.media.present

    implicitWidth: lyr.item ? lyr.item.implicitWidth : 0
    implicitHeight: lyr.item ? lyr.item.implicitHeight : 0

    Loader {
        id: lyr
        active: root.present || root.preview

        sourceComponent: LockLyrics {
            media: root.media
            px: root.px
            maxWidth: root.px(900)
            always: true
            preview: root.preview
        }
    }
}
