import QtQuick
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "ReaderMath.js" as RM

// The poster tile of the manga / novel grids, built as one of the shell's own cards: the
// Pill's navy outline (and inner ring in the dark modes), a hard shadow underneath, and the
// press that sinks the card into that shadow. The cover is cut to the card's rounded
// corners and sits over a title strip that is divided from it by the same outline.
//
// Anything else the grid needs (a stamp, the progress strip) is added as an ordinary child
// and lands on top of the cover. Tell the card how tall the bottom strip is via
// `footerHeight` so the cover and title bar size around it.
Item {
    id: root

    property url source: ""
    property string title: ""
    property string subtitle: ""
    property string bodyFont: Theme.fontFamily
    // Kept for the call sites that set it: the strip between cover and title is a hard line now.
    property int gradientHeight: 0
    property int footerHeight: 0
    // The whole title, however long, over the bottom of the cover on a dark fade, instead of
    // two elided lines in a strip under it. The cover keeps the same size for every title, so
    // the grid does not change with how long a name is.
    property bool fullTitle: false
    // Keep the wrap of the titles at the old width while the panel changes width (see below).
    // A grid that holds its own layout during the move (the manga Browse / Saved grids) turns it
    // off: its covers are already their final width on the first frame.
    property bool holdTitle: true

    // The width the titles are wrapped at. It follows the card, except while the panel changes
    // its width (ReaderEnv.panelResizing): wrapping and eliding the title of every cover of a
    // grid again on every frame of that was a large part of the stutter. They keep the width
    // they had (the card only grows or shrinks around them) and take the new one when it ends.
    readonly property real titleWidthNow: titleBar.width - 18
    property real titleWidth: titleWidthNow
    onTitleWidthNowChanged: if (!root.holdTitle || !ReaderEnv.panelResizing) root.titleWidth = root.titleWidthNow
    Connections {
        target: ReaderEnv
        function onPanelResizingChanged() {
            if (!ReaderEnv.panelResizing)
                root.titleWidth = root.titleWidthNow
        }
    }

    // The title strip has one height whatever the title is: room for two lines of title (and the
    // subtitle line when there is one). It used to be as tall as the text it held, so a title
    // that wrapped to two lines at one width and one line at the other changed the strip's
    // height when the panel finished changing width, and with it the height of every cover: a
    // visible jump of the whole grid and a layout of every card at the end of the move.
    FontMetrics {
        id: titleMetrics
        font.family: root.bodyFont
        font.pixelSize: ReaderType.sizeCaption
        font.weight: ReaderType.weightTitle
        font.styleName: ReaderType.styleTitle
    }
    FontMetrics {
        id: subtitleMetrics
        font.family: root.bodyFont
        font.pixelSize: ReaderType.sizeCaption
    }
    readonly property real titleLineHeight: Math.ceil(titleMetrics.height * 1.15)
    readonly property real stripHeight: 2 * root.titleLineHeight
                                        + (root.subtitle.length > 0 ? 2 + Math.ceil(subtitleMetrics.height) : 0)
                                        + 14

    // No hover while the panel changes width: the cards move under a pointer that stands still,
    // and every card that passed under it played its hover (cover zoom, strip colour) for a few
    // frames in the middle of the move.
    readonly property bool hovered: tap.containsMouse && !ReaderEnv.panelResizing
    readonly property bool pressed: tap.pressed

    signal clicked()

    default property alias content: extras.data

    anchors.margins: 5

    Pill {
        id: card
        anchors.fill: parent
        cornerRadius: 13
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface
        pressed: tap.pressed

        ClippingRectangle {
            id: clipBox
            anchors.fill: parent
            radius: Math.max(0, card.cornerRadius - card.ringWidth)
            color: "transparent"

            // Beside the cover, not inside it: the cover sits at opacity 0 until it's
            // ready, which would hide a child placeholder too.
            CoverPlaceholder {
                anchors.fill: cover
                status: cover.status
            }

            Image {
                id: cover
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: clipBox.height - (root.fullTitle ? 0 : titleBar.height) - root.footerHeight

                // A cover that failed (the image proxy / CDN hiccuped under the burst of
                // requests a full grid makes) used to stay failed until the panel was closed
                // and reopened, because an Image never retries the same source. Retry a few
                // times with a growing delay, tagging the URL so Qt asks again instead of
                // reusing the failed load. The proxy ignores the extra query key.
                property int attempt: 0
                readonly property int maxAttempts: 4
                // The sharper AniList size is asked for first; if the CDN does not have it
                // (an Error), the original URL is used instead of retrying a dead one.
                property bool useOriginal: false
                readonly property string rawBase: root.source.toString()
                readonly property string base: useOriginal ? rawBase : RM.hiResCover(rawBase)
                source: base.length === 0 ? ""
                      : (attempt === 0 ? base
                         : base + (base.indexOf("?") >= 0 ? "&" : "?") + "retry=" + attempt)
                onRawBaseChanged: { useOriginal = false; attempt = 0 }
                onStatusChanged: {
                    if (status !== Image.Error || base.length === 0) return
                    if (!useOriginal && base !== rawBase) { useOriginal = true; attempt = 0; return }
                    if (attempt < maxAttempts) retryTimer.restart()
                }
                Timer {
                    id: retryTimer
                    interval: 800 * Math.pow(2, cover.attempt)   // 0.8s, 1.6s, 3.2s, 6.4s
                    onTriggered: cover.attempt++
                }

                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                // Decoded at about twice the card's size (rounded up to a step of 64 so a resize
                // does not reload it): Qt shrinks a big cover once, with its good filter, instead
                // of the GPU squashing the full image every frame.
                sourceSize.width: width > 0 ? Math.ceil(width * 2 / 64) * 64 : 0
                sourceSize.height: height > 0 ? Math.ceil(height * 2 / 64) * 64 : 0
                opacity: status === Image.Ready ? 1 : 0
                scale: root.hovered ? 1.04 : 1
                Behavior on opacity { NumberAnimation { duration: 300 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: titleBar
                anchors {
                    bottom: parent.bottom
                    bottomMargin: root.footerHeight
                    left: parent.left
                    right: parent.right
                }
                // A strip is as tall as two title lines; the fade is as tall as the whole title.
                height: root.fullTitle ? titleColumn.implicitHeight + 34 : root.stripHeight
                color: root.fullTitle ? "transparent" : (root.hovered ? Theme.surfaceTint : Theme.surface)
                Behavior on color { ColorAnimation { duration: 130 } }
                gradient: root.fullTitle ? scrim : null

                Gradient {
                    id: scrim
                    GradientStop { position: 0.0;  color: Qt.rgba(0.07, 0.05, 0.11, 0.0) }
                    GradientStop { position: 0.45; color: Qt.rgba(0.07, 0.05, 0.11, 0.62) }
                    GradientStop { position: 1.0;  color: Qt.rgba(0.07, 0.05, 0.11, 0.92) }
                }

                // The panel line between cover and title.
                Rectangle {
                    visible: !root.fullTitle
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 2
                    color: Theme.line
                }

                Column {
                    id: titleColumn
                    anchors {
                        left: parent.left; right: parent.right
                        leftMargin: 9; rightMargin: 9
                    }
                    // In the middle of the strip, or at the foot of the cover.
                    y: root.fullTitle ? parent.height - height - 9 : (parent.height - height) / 2 + 1
                    spacing: 2

                    Text {
                        width: root.titleWidth
                        // Always two lines tall; a one-line title sits in the middle of them.
                        height: root.fullTitle ? implicitHeight : 2 * root.titleLineHeight
                        verticalAlignment: Text.AlignVCenter
                        text: root.title
                        color: root.fullTitle ? ReaderType.tagInk : Theme.ink
                        font.family: root.bodyFont
                        font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightTitle
                        font.styleName: ReaderType.styleTitle
                        wrapMode: Text.Wrap
                        maximumLineCount: root.fullTitle ? 2147483647 : 2
                        elide: root.fullTitle ? Text.ElideNone : Text.ElideRight
                        lineHeight: 1.15
                    }

                    Text {
                        visible: root.subtitle.length > 0
                        width: root.titleWidth
                        text: root.subtitle
                        color: root.fullTitle ? Qt.rgba(0.95, 0.93, 0.97, 0.72) : Theme.inkSub
                        font.family: root.bodyFont
                        font.pixelSize: ReaderType.sizeCaption
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                id: extras
                anchors.fill: parent
            }
        }
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
