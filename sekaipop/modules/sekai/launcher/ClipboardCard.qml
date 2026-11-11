import QtQuick
import Quickshell
import "../../common/functions/Extras.js" as X
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.phone

// Clipboard history, made for the phone: one column. The list of what you
// copied scrolls on top (mouse wheel, Up / Down, or drag), and a sheet at the
// bottom shows the whole of whatever is picked -- read all of it, select part of
// it with the mouse, or copy the lot with the Copy key (or Enter). Images that
// were copied show as a picture. Typing after "clip " filters the list. Click
// an entry to pick it, double-click to copy it right away.
//
// The pin key (or Ctrl+P) keeps the picked entry: pinned ones sit at the top with a
// pin on their disc and outlive the history (its size cap, Clear history, Delete).
// Press it again, or Delete, to let a pin go.
//
// Pure UI. `entries` is the (already filtered) list from ExtrasSource --
// pins first ({ ..., pinned: true }, ClipPins.js), then
// [{ id, preview, image, line }], newest first -- and `fullText` /
// `fullImage` are the picked entry's contents, which ExtrasSource loads when
// this card reports a new pick (`highlighted`).
PhoneCard {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property var entries: []
    property bool available: true
    property string fullText: ""
    property string fullImage: ""
    // The whole entry is still being fetched / could not be fetched. Until it is
    // here the card does not show the short preview as if it were the text.
    property bool loading: false
    property bool failed: false
    // What the decoder said when it failed (its stderr), shown under the message.
    property string error: ""
    property string filter: ""

    property int current: 0
    readonly property var currentEntry: (current >= 0 && current < entries.length) ? entries[current] : null

    signal highlighted(var entry)
    signal copyRequested(var entry)
    signal deleteRequested(var entry)
    signal pinRequested(var entry)
    signal closeRequested()

    // The id of the picked entry, so a refresh that shifts every index
    // (a new copy lands on top) keeps the same entry picked.
    property string currentId: ""

    // The entry at index i, read straight from `entries`. The change handlers below
    // must use this and NOT `currentEntry`: inside onEntriesChanged / onCurrentChanged
    // that binding has not been re-evaluated yet, so it still holds the PREVIOUS
    // entry (or null). Using it made the sheet show the entry one step behind the
    // one that was highlighted, and left the newest entry blank.
    function entryAt(i) {
        return (i >= 0 && i < entries.length) ? entries[i] : null
    }

    onEntriesChanged: {
        let idx = -1
        if (currentId !== "") {
            for (let i = 0; i < entries.length; i++) {
                if (entries[i].id === currentId) {
                    idx = i
                    break
                }
            }
        }
        if (idx < 0)
            idx = 0
        if (idx !== current)
            current = idx            // onCurrentChanged reports the pick
        else
            highlighted(entryAt(current))
    }
    onCurrentChanged: {
        const e = entryAt(current)
        currentId = e ? e.id : ""
        list.positionViewAtIndex(Math.max(0, current), ListView.Contain)
        highlighted(e)
    }
    onFilterChanged: {
        currentId = ""
        current = 0
    }

    function nav(dx, dy) {
        if (entries.length === 0)
            return
        current = Math.max(0, Math.min(entries.length - 1, current + dy + dx))
    }

    function activate() {
        const e = entryAt(current)
        if (e)
            copyRequested(e)
    }

    // Ctrl+P from the search box (LauncherFace.qml): the pin key.
    function togglePin() {
        const e = entryAt(current)
        if (e)
            pinRequested(e)
    }

    readonly property color darkInk: mt.colBorder

    // ===== the room =====
    readonly property real headH: 44
    readonly property real barH: 62
    readonly property real rowH: 58
    readonly property real rowGap: 8
    readonly property real listY: headH + 12
    // The sheet wants about two fifths of the page, never less than it needs. The
    // list then shows whole rows only (no row cut off at the bottom), and the sheet
    // takes the little that is left over.
    readonly property real sheetWant: Math.max(214, Math.min(340, Math.round(pageH * 0.42)))
    readonly property int listRows: Math.max(1, Math.floor((pageH - listY - 12 - sheetWant + rowGap) / (rowH + rowGap)))
    readonly property real listH: listRows * (rowH + rowGap) - rowGap
    readonly property real sheetH: pageH - listY - listH - 12

    // ===== head: what this is, and how many =====
    Item {
        id: head

        width: root.pageW
        height: root.headH

        MaterialIcon {
            id: headIcon
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            name: "content_paste"
            size: 30
            weight: 600
        }

        Text {
            anchors.left: headIcon.right
            anchors.leftMargin: 12
            anchors.right: countChip.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.filter === "" ? "Clipboard" : "Matching \u201c" + X.oneLine(root.filter, 18) + "\u201d"
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 26
            font.weight: Font.ExtraBold
        }

        PhonePlate {
            id: countChip

            visible: root.available
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(54, countText.implicitWidth + 36)
            height: 38
            radius: (height - shadow) / 2
            borderW: 2.5
            shadow: 3
            fill: mt.accentCyan

            Text {
                id: countText
                anchors.centerIn: parent
                text: root.entries.length
                color: root.darkInk
                font.family: mt.fontFamily
                font.pixelSize: 18
                font.weight: Font.ExtraBold
            }
        }
    }

    // ===== the list =====
    WheelScroll { scroller: list }
    ListView {
        id: list

        x: 0
        y: root.listY
        width: root.pageW
        height: root.listH
        clip: true
        spacing: root.rowGap
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries
        currentIndex: root.current
        visible: root.entries.length > 0

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool sel: index === root.current

            width: list.width
            height: root.rowH

            PhonePlate {
                anchors.fill: parent
                radius: (height - shadow) / 2
                borderW: row.sel ? 5 : 3
                fill: row.sel ? mt.accentMint : (rowArea.containsMouse ? mt.pSurfaceHover : mt.pSurface)

                Rectangle {
                    id: glyphDisc
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: row.sel ? Qt.rgba(1, 1, 1, 0.55) : mt.pSurfaceHover

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: row.modelData.pinned ? "push_pin" : (row.modelData.image ? "image" : "notes")
                        fill: row.modelData.pinned ? 1 : mt.iconFill
                        size: 22
                        weight: 600
                        color: row.sel ? root.darkInk : mt.pInkSub
                    }
                }

                Text {
                    anchors.left: glyphDisc.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.modelData.image ? X.imageLabel(row.modelData.preview) : X.oneLine(row.modelData.preview, 80)
                    color: row.sel ? root.darkInk : mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 20
                    font.weight: row.sel ? Font.ExtraBold : Font.Bold
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.current = row.index
                onDoubleClicked: root.copyRequested(row.modelData)
            }
        }
    }

    // a thin scroll cue for a long list, out in the phone's margin on the right
    Rectangle {
        visible: list.visible && list.contentHeight > list.height
        x: root.pageW + 11
        y: list.y + (list.height - height) * (list.contentY / Math.max(1, list.contentHeight - list.height))
        width: 6
        height: Math.max(30, list.height * list.height / Math.max(1, list.contentHeight))
        radius: 3
        color: mt.pSurfaceRing
        antialiasing: true
    }

    // empty / unavailable
    Text {
        x: 20
        y: root.headH + 40
        width: root.pageW - 40
        height: list.height - 40
        visible: root.entries.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: mt.pInkSub
        font.family: mt.fontFamily
        font.pixelSize: 21
        font.weight: Font.Bold
        lineHeight: 1.25
        text: !root.available
            ? "Clipboard history needs cliphist and wl-clipboard. Install both and restart the shell \u2014 it fills as you copy."
            : (root.filter !== "" ? "Nothing in your history matches that." : "Nothing copied yet.\nCopy something and it will show up here.")
    }

    // ===== the sheet: the whole of the picked entry =====
    PhonePlate {
        id: sheet

        y: root.pageH - root.sheetH
        width: root.pageW
        height: root.sheetH
        radius: 32

        // the text well
        Rectangle {
            id: well

            x: 14
            y: 14
            width: sheet.faceW - 28
            height: sheet.faceH - 28 - root.barH + 6
            radius: 20
            color: mt.pSurfaceHover
            clip: true

            // text entry: everything, selectable
            WheelScroll { scroller: flick }
            Flickable {
                id: flick

                anchors.fill: parent
                anchors.margins: 14
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: root.currentEntry !== null && !root.currentEntry.image
                flickableDirection: Flickable.VerticalFlick

                TextEdit {
                    id: body
                    width: flick.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    // the whole text; the short preview only when it could not be loaded
                    text: root.loading ? "" : (root.fullText !== "" || !root.failed ? root.fullText : (root.currentEntry ? root.currentEntry.preview : ""))
                    color: mt.pInk
                    selectionColor: mt.accentCyan
                    selectedTextColor: root.darkInk
                    font.family: "monospace"
                    font.pixelSize: 17
                    Keys.onEscapePressed: root.closeRequested()
                }
            }

            // image entry
            Image {
                id: pic
                anchors.fill: parent
                anchors.margins: 10
                visible: root.currentEntry !== null && root.currentEntry.image && !root.loading
                source: root.fullImage
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false // one-off preview of a temp file; don't keep decoded copies of every image browsed
                smooth: true
                // A copied screenshot can be 4K+ (30 MB+ decoded). The preview
                // is a small card, so decode it to at most this box.
                sourceSize: Qt.size(1400, 1400)
            }

            // the picture could not be read (a format Qt does not know)
            Text {
                anchors.fill: parent
                anchors.margins: 14
                visible: pic.visible && pic.status === Image.Error
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 19
                font.weight: Font.Bold
                text: "This picture can\u2019t be shown here (its format is not supported).\nCopy still puts it back on the clipboard."
            }

            Text {
                anchors.centerIn: parent
                visible: root.currentEntry === null || root.loading || (root.failed && root.currentEntry.image && root.fullImage === "")
                width: parent.width - 28
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.currentEntry === null ? "Pick something above"
                    : (root.loading ? "Loading\u2026"
                        : "Could not load this picture" + (root.error !== "" ? "\n" + X.oneLine(root.error, 120) : ""))
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
            }

            // little scroll cue for long text
            Rectangle {
                visible: flick.visible && flick.contentHeight > flick.height
                x: parent.width - 11
                y: 14 + (flick.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
                width: 6
                height: Math.max(24, flick.height * flick.height / Math.max(1, flick.contentHeight))
                radius: 3
                color: mt.pSurfaceRing
                antialiasing: true
            }
        }

        // the keys under the well: what it is, delete, copy
        Item {
            x: 14
            y: well.y + well.height + 6
            width: sheet.faceW - 28
            height: root.barH - 14

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: pinKey.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 17
                font.weight: Font.Bold
                text: {
                    const e = root.currentEntry
                    if (!e)
                        return ""
                    const pin = e.pinned ? "Pinned \u00b7 " : ""
                    if (e.image)
                        return pin + X.imageLabel(e.preview)
                    if (root.loading)
                        return "Loading\u2026"
                    if (root.failed && root.fullText === "")
                        return "Preview only \u2014 the whole entry could not be loaded"
                    const t = root.fullText
                    const lines = t.split("\n").length
                    return pin + t.length + " characters \u00b7 " + lines + (lines === 1 ? " line" : " lines")
                }
            }

            // Lit (cyan, the pin filled in) while the picked entry is pinned.
            PhoneKey {
                id: pinKey
                readonly property bool pinnedNow: root.currentEntry !== null && root.currentEntry.pinned === true
                anchors.right: delKey.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 50
                icon: "push_pin"
                iconSize: 26
                fill: pinnedNow ? mt.accentCyan : mt.pSurface
                ink: pinnedNow ? root.darkInk : mt.pInk
                enabled: root.currentEntry !== null
                onClicked: root.pinRequested(root.currentEntry)
            }

            PhoneKey {
                id: delKey
                anchors.right: copyKey.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 50
                icon: "delete"
                iconSize: 26
                fill: ScrapbookTheme.tapePink
                ink: root.darkInk
                enabled: root.currentEntry !== null
                onClicked: root.deleteRequested(root.currentEntry)
            }

            PhoneKey {
                id: copyKey
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                height: 50
                label: "Copy"
                fontSize: 22
                fill: mt.accentMint
                ink: root.darkInk
                enabled: root.currentEntry !== null
                onClicked: root.activate()
            }
        }
    }
}
