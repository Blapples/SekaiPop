import QtQuick
import Quickshell
import QtQuick.Effects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The PRESETS tab of Edit Desktop's shelf (EditTray.qml): the desktop's whole
// look, saved under a name and worn again with one click. What a preset
// holds and what it leaves alone is written at the top of
// services/DesktopPresetService.qml.
//
//   first tile       SAVE THIS LOOK: click, type a name, Enter. Esc cancels. A NOT SAVED
//                    badge on it: no preset is the desktop as it is now, so wearing one
//                    would leave this look only in the UNDO tile.
//   UNDO tiles       after the first tile, while there is something to undo: UNDO wears
//                    the look the last preset replaced, and turns into REDO, which wears
//                    the undone look again (and turns back into UNDO); UNDELETE brings
//                    the last deleted preset back. See "Undo" in DesktopPresetService.qml.
//   click a tile     wear that preset. The card above changes live (colours,
//                    bar, widgets, wallpaper, Quick Panel buttons).
//   hover a tile     a SAVE OVER button comes up on its picture: click it
//                    twice to replace that preset with the desktop as it is now.
//   pencil on a tile the pencil next to SAVE OVER renames that preset: the name turns
//                    into a field, Enter keeps it, Esc cancels. A name another
//                    preset has (or an empty one) is refused, the field goes red.
//   star on a tile   the badge on the tile's top-left corner pins the preset: favourites stand
//                    first in the row (then the rest, by name). It comes up on hover; a pinned
//                    tile keeps its gold star showing.
//   right click      DELETE: right click twice (it asks first).
//   tick on a tile   the desktop is exactly that preset right now. It goes
//                    away as soon as you change anything.
//   mouse wheel      scrolls the row sideways, if the tiles do not all fit
//
// Each tile is drawn from what the preset holds: its wallpaper, the two
// accent colours of its theme, and a light / dark mark. Tile size lives in
// `tileW` / `tileH`: the shelf is 168 tall, so keep tileH under about 140
// (the tick badge pokes out above the tile).
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    readonly property real tileW: 150
    readonly property real tileH: 138

    // Tells the shelf to take the keyboard back after the name field gave it
    // up, so Esc leaves Edit Desktop again (EditTray.qml listens).
    signal finished()

    // The picture file for a wallpaper path: the cached thumbnail, a video's
    // first frame, or nothing yet.
    function imageUrl(path) {
        if (!path)
            return ""
        if (WallpaperService.isVideo(path)) {
            const still = WallpaperService.stills[path]
            if (!still)
                return ""
            return still.indexOf("/") === 0 ? "file://" + still : still
        }
        return WallpaperService.thumbUrl(path)
    }

    // What the desktop is now, kept fresh while this tab shows, so the tick
    // on a tile is honest. (One capture a second is a few kilobytes of text.)
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: DesktopPresetService.refreshLive()
    }

    onVisibleChanged: {
        if (root.visible)
            DesktopPresetService.refresh()
    }

    // No preset is the desktop as it is now (the NOT SAVED badge on the first tile).
    readonly property bool unsaved: DesktopPresetService.loaded
        && !DesktopPresetService.presets.some(p => DesktopPresetService.isCurrent(p.data))

    // ===== the first tile: save the desktop as it is =====
    component NewTile: Item {
        id: nt

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property bool naming: false

        width: root.tileW
        height: root.tileH

        Gradient {
            id: onFill
            GradientStop { position: 0.0; color: mt.accentMint }
            GradientStop { position: 1.0; color: mt.accentCyan }
        }

        function begin() {
            nt.naming = true
            input.text = DesktopPresetService.suggestName()
            Qt.callLater(() => {
                input.forceActiveFocus()
                input.selectAll()
            })
        }

        function cancel() {
            nt.naming = false
            input.focus = false
            root.finished()
        }

        function commit() {
            DesktopPresetService.saveNew(input.text)
            nt.cancel()
        }

        // Leaving the tab (or Edit Desktop) drops a half-typed name.
        Connections {
            target: root

            function onVisibleChanged() {
                if (!root.visible && nt.naming)
                    nt.naming = false
            }
        }

        Pill {
            id: body
            width: nt.width
            height: nt.height
            y: addArea.containsMouse && !nt.naming && !addArea.pressed ? -3 : 0
            cornerRadius: 15
            ringWidth: 4
            shadowDx: 0
            shadowDy: 4
            pressed: addArea.pressed && !nt.naming
            fillColor: addArea.containsMouse && !nt.naming ? mt.pSurfaceHover : mt.pSurface

            Behavior on y {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            // Resting: a plus in a gradient disc and what it does.
            Column {
                visible: !nt.naming
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                spacing: 8

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54
                    height: 54
                    radius: 27
                    gradient: onFill
                    border.width: 3
                    border.color: mt.pLine
                    antialiasing: true

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "add"
                        size: 32
                        weight: 700
                        color: mt.colBorder
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SAVE THIS LOOK"
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 0.6
                }
            }

            // Naming: a field, and what the keys do.
            Column {
                visible: nt.naming
                anchors.centerIn: parent
                width: body.capWidth - body.ringWidth * 2 - 20
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "NAME IT"
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 0.8
                }

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 11
                    color: mt.chipFill
                    border.width: 3
                    border.color: mt.pLine
                    antialiasing: true

                    MouseArea {
                        anchors.fill: parent
                        onPressed: input.forceActiveFocus()
                    }

                    TextInput {
                        id: input
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        maximumLength: 40
                        selectByMouse: true
                        color: mt.chipInk
                        selectionColor: mt.accentCyan
                        selectedTextColor: mt.colBorder
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold

                        Keys.onReturnPressed: nt.commit()
                        Keys.onEnterPressed: nt.commit()
                        Keys.onEscapePressed: event => {
                            event.accepted = true
                            nt.cancel()
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Enter: save   Esc: cancel"
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        // NOT SAVED: on the corner, where a preset tile has its star.
        Rectangle {
            visible: root.unsaved && !nt.naming
            x: -8
            y: -8
            width: unsavedText.width + 16
            height: 22
            radius: 11
            color: "#ffd04a"
            border.width: 2
            border.color: mt.pLine
            antialiasing: true

            Text {
                id: unsavedText
                anchors.centerIn: parent
                text: "NOT SAVED"
                color: mt.colBorder
                font.family: mt.fontFamily
                font.pixelSize: 9
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
                font.letterSpacing: 0.5
            }
        }

        MouseArea {
            id: addArea
            anchors.fill: parent
            enabled: !nt.naming
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: nt.begin()
        }
    }

    // ===== undo: the look before the last preset, or the last preset deleted =====
    component UndoTile: Item {
        id: ut

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string icon: "undo"
        property string title: ""
        property string sub: ""
        signal activated()

        width: root.tileW
        height: root.tileH

        Pill {
            width: ut.width
            height: ut.height
            y: undoArea.containsMouse && !undoArea.pressed ? -3 : 0
            cornerRadius: 15
            ringWidth: 4
            shadowDx: 0
            shadowDy: 4
            pressed: undoArea.pressed
            fillColor: undoArea.containsMouse ? mt.pSurfaceHover : mt.pSurface

            Behavior on y {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                width: root.tileW - 24
                spacing: 6

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54
                    height: 54
                    radius: 27
                    color: mt.chipFill
                    border.width: 3
                    border.color: mt.pLine
                    antialiasing: true

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: ut.icon
                        size: 30
                        weight: 700
                        color: mt.chipInk
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ut.title
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 0.6
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: ut.sub
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        MouseArea {
            id: undoArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: ut.activated()
        }
    }

    // ===== one saved preset =====
    component PresetTile: Item {
        id: tile

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        required property var entry

        readonly property var d: entry.data
        readonly property bool favorite: DesktopPresetService.isFavorite(tile.entry)
        readonly property bool selected: DesktopPresetService.isCurrent(tile.d)
        readonly property var themeInfo: tile.d.theme ?? ({})
        readonly property var palette: {
            if (tile.themeInfo.group === "custom") {
                const own = ThemeService.customShell(tile.themeInfo.custom)
                if (own)
                    return own
            }
            const g = ThemeService.groups.find(x => x.id === tile.themeInfo.group)
            return g ? g.c : ThemeService.baseGroups[0].c
        }
        readonly property string modeName: tile.themeInfo.mode ?? "light"
        readonly property string picture: root.imageUrl(DesktopPresetService.previewPath(tile.d))

        Gradient {
            id: onFill
            GradientStop { position: 0.0; color: mt.accentMint }
            GradientStop { position: 1.0; color: mt.accentCyan }
        }

        // "" | "overwrite" | "delete": the button that was pressed once and
        // waits for a second press. It lapses by itself.
        property string armed: ""

        width: root.tileW
        height: root.tileH

        // Renaming: the name under the picture is a field. `nameBad` turns it red
        // when the name was refused (empty, or another preset has it).
        property bool renaming: false
        property bool nameBad: false

        function beginRename() {
            tile.disarm()
            tile.nameBad = false
            tile.renaming = true
            nameInput.text = tile.entry.name
            Qt.callLater(() => {
                nameInput.forceActiveFocus()
                nameInput.selectAll()
            })
        }

        function endRename() {
            tile.renaming = false
            tile.nameBad = false
            nameInput.focus = false
            root.finished()
        }

        function commitRename() {
            if (DesktopPresetService.rename(tile.entry.name, nameInput.text) === "") {
                tile.nameBad = true
                return
            }
            tile.endRename()
        }

        // Leaving the tab (or Edit Desktop) drops a half-typed name.
        Connections {
            target: root

            function onVisibleChanged() {
                if (!root.visible && tile.renaming)
                    tile.renaming = false
            }
        }

        function arm(kind) {
            tile.armed = kind
            armTimer.restart()
        }

        function disarm() {
            tile.armed = ""
            armTimer.stop()
        }

        Timer {
            id: armTimer
            interval: 2800
            onTriggered: tile.armed = ""
        }

        // The whole tile. Declared BEFORE the picture, so the SAVE OVER button
        // (inside it) sits above and wins the clicks over its own corner.
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onExited: tile.disarm()

            onClicked: mouse => {
                if (tile.renaming)
                    return
                if (mouse.button === Qt.RightButton) {
                    if (tile.armed === "delete") {
                        tile.disarm()
                        DesktopPresetService.remove(tile.entry.name)
                    } else {
                        tile.arm("delete")
                    }
                    return
                }
                if (tile.armed !== "") {
                    tile.disarm()
                    return
                }
                DesktopPresetService.apply(tile.entry.name)
            }
        }

        Pill {
            id: body
            width: tile.width
            height: tile.height
            y: tileArea.containsMouse && !tile.selected && !tileArea.pressed ? -3 : 0
            cornerRadius: 15
            ringWidth: 4
            shadowDx: 0
            shadowDy: 4
            pressed: tileArea.pressed
            fillColor: tileArea.containsMouse && !tile.selected ? mt.pSurfaceHover : mt.pSurface
            fillGradient: tile.selected ? onFill : null

            Behavior on y {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            // ===== the picture =====
            Item {
                id: pic
                x: 6
                y: 6
                width: body.capWidth - body.ringWidth * 2 - 12
                height: 92

                // Its hard drop shadow, then the frame with the wallpaper in it.
                Rectangle {
                    y: 3
                    width: parent.width
                    height: parent.height - 3
                    radius: 10
                    color: tile.palette.border
                    antialiasing: true
                }

                Rectangle {
                    id: frame
                    width: parent.width
                    height: parent.height - 3
                    radius: 10
                    color: Qt.color(tile.palette.boardBg)
                    border.width: 3
                    border.color: tile.palette.border
                    antialiasing: true

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: photo.status !== Image.Ready
                        name: "wallpaper"
                        size: 30
                        color: tile.palette.border
                        opacity: 0.35
                    }

                    // The wallpaper, cut to the frame's rounded inside (an
                    // Image is a plain rectangle: without the mask its
                    // corners would poke out past the frame, see WallpaperCard).
                    Item {
                        id: photoClip
                        x: frame.border.width
                        y: frame.border.width
                        width: frame.width - frame.border.width * 2
                        height: frame.height - frame.border.width * 2

                        layer.enabled: true
                        layer.smooth: true
                        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * 2)),
                                                   Math.max(1, Math.ceil(height * 2)))
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: photoMask
                        }

                        Image {
                            id: photo
                            anchors.fill: parent
                            source: tile.picture
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            smooth: true
                            sourceSize.width: 320
                            opacity: status === Image.Ready ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 180
                                }
                            }
                        }
                    }

                    Item {
                        id: photoMask
                        x: photoClip.x
                        y: photoClip.y
                        width: photoClip.width
                        height: photoClip.height
                        visible: false
                        layer.enabled: true
                        layer.smooth: true
                        layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * 2)),
                                                   Math.max(1, Math.ceil(height * 2)))

                        Rectangle {
                            anchors.fill: parent
                            radius: 7
                            color: "black"
                            antialiasing: true
                        }
                    }

                    // The theme's two accents and its look, in the corner.
                    Row {
                        x: 8
                        y: frame.height - 21
                        spacing: 4

                        Rectangle {
                            width: 13
                            height: 13
                            radius: 6.5
                            color: tile.palette.A
                            border.width: 2
                            border.color: tile.palette.border
                            antialiasing: true
                        }

                        Rectangle {
                            width: 13
                            height: 13
                            radius: 6.5
                            color: tile.palette.B
                            border.width: 2
                            border.color: tile.palette.border
                            antialiasing: true
                        }
                    }

                    Rectangle {
                        x: frame.width - width - 8
                        y: frame.height - height - 8
                        width: 20
                        height: 20
                        radius: 10
                        color: tile.palette.border
                        antialiasing: true

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: tile.modeName === "light" ? "light_mode"
                                : (tile.modeName === "darker" ? "contrast" : "dark_mode")
                            size: 13
                            weight: 700
                            color: "#ffffff"
                        }
                    }
                }

                // "Press again": the tile waits for the second press.
                Rectangle {
                    anchors.fill: frame
                    radius: 10
                    visible: tile.armed === "delete"
                    color: "#d83a5c"
                    opacity: 0.93
                    antialiasing: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "delete"
                            size: 24
                            weight: 700
                            color: "#ffffff"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "DELETE?"
                            color: "#ffffff"
                            font.family: mt.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "right click again"
                            color: "#ffffff"
                            font.family: mt.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // RENAME: a pencil in the other corner, on hover; one press turns the
                // name into a field.
                Rectangle {
                    id: renameBtn
                    visible: (tileArea.containsMouse || renameArea.containsMouse)
                        && tile.armed === "" && !tile.renaming
                    x: 6
                    y: 6
                    width: 22
                    height: 22
                    radius: 11
                    color: renameArea.containsMouse ? mt.accentMint : mt.chipFill
                    border.width: 2
                    border.color: mt.pLine
                    antialiasing: true

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "edit"
                        size: 13
                        weight: 700
                        color: renameArea.containsMouse ? mt.colBorder : mt.chipInk
                    }

                    MouseArea {
                        id: renameArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.beginRename()
                    }
                }

                // SAVE OVER: comes up on hover; the second press does it.
                Rectangle {
                    id: overBtn
                    visible: (tileArea.containsMouse || overArea.containsMouse || tile.armed === "overwrite")
                        && tile.armed !== "delete" && !tile.renaming
                    x: frame.width - width - 6
                    y: 6
                    width: overRow.width + 14
                    height: 22
                    radius: 11
                    color: tile.armed === "overwrite" ? "#d83a5c" : mt.chipFill
                    border.width: 2
                    border.color: mt.pLine
                    antialiasing: true

                    Row {
                        id: overRow
                        anchors.centerIn: parent
                        spacing: 3

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "sync"
                            size: 13
                            weight: 700
                            color: tile.armed === "overwrite" ? "#ffffff" : mt.chipInk
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.armed === "overwrite" ? "SURE?" : "SAVE OVER"
                            color: tile.armed === "overwrite" ? "#ffffff" : mt.chipInk
                            font.family: mt.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                            font.letterSpacing: 0.5
                        }
                    }

                    MouseArea {
                        id: overArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tile.armed === "overwrite") {
                                tile.disarm()
                                DesktopPresetService.overwrite(tile.entry.name)
                            } else {
                                tile.arm("overwrite")
                            }
                        }
                    }
                }
            }

            // ===== the name =====
            // While renaming: a field in its place (the same one as the SAVE THIS
            // LOOK tile's).
            Rectangle {
                visible: tile.renaming
                x: 6
                y: pic.y + pic.height + 3
                width: pic.width
                height: 26
                radius: 9
                color: mt.chipFill
                border.width: 3
                border.color: tile.nameBad ? "#d83a5c" : mt.pLine
                antialiasing: true

                // Catches the clicks on the field's rim, which would otherwise wear
                // the preset.
                MouseArea {
                    anchors.fill: parent
                    onPressed: nameInput.forceActiveFocus()
                }

                TextInput {
                    id: nameInput
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    maximumLength: 40
                    selectByMouse: true
                    color: tile.nameBad ? "#d83a5c" : mt.chipInk
                    selectionColor: mt.accentCyan
                    selectedTextColor: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold

                    onTextChanged: tile.nameBad = false

                    Keys.onReturnPressed: tile.commitRename()
                    Keys.onEnterPressed: tile.commitRename()
                    Keys.onEscapePressed: event => {
                        event.accepted = true
                        tile.endRename()
                    }
                }
            }

            Text {
                visible: !tile.renaming
                x: 6
                y: pic.y + pic.height + 6
                width: pic.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.entry.name
                color: tile.selected ? mt.colBorder : mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        // FAVOURITE: a star on the opposite corner, outside the picture so it never
        // fights the pencil and SAVE OVER for room. Click it to pin the preset to the
        // front of the row (or let it go). It comes up on hover; a pinned tile keeps
        // its filled gold star showing.
        Rectangle {
            id: starBtn
            visible: (tile.favorite || tileArea.containsMouse || starArea.containsMouse)
                && tile.armed !== "delete" && !tile.renaming
            x: -8
            y: -8
            width: 24
            height: 24
            radius: 12
            color: tile.favorite ? "#ffd04a" : (starArea.containsMouse ? mt.accentMint : mt.chipFill)
            border.width: 2
            border.color: mt.pLine
            antialiasing: true

            MaterialIcon {
                anchors.centerIn: parent
                name: "star"
                size: 15
                weight: 700
                fill: tile.favorite ? 1 : 0
                color: tile.favorite || starArea.containsMouse ? mt.colBorder : mt.chipInk
            }

            MouseArea {
                id: starArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: DesktopPresetService.toggleFavorite(tile.entry.name)
            }
        }

        // The one the desktop is right now: a tick on the corner.
        Rectangle {
            visible: tile.selected
            x: tile.width - 17
            y: -8
            width: 24
            height: 24
            radius: 12
            color: mt.accentMint
            border.width: 2
            border.color: mt.pLine
            antialiasing: true

            MaterialIcon {
                anchors.centerIn: parent
                name: "check"
                size: 15
                weight: 700
                color: mt.colBorder
            }
        }

    }

    // The row. Centred; if the tiles do not all fit, it scrolls sideways.
    Flickable {
        id: flick
        anchors.fill: parent

        contentWidth: Math.max(flick.width, row.width)
        contentHeight: flick.height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        // Not clipped while everything fits, so the tick badge and the lift
        // can poke out above the tiles.
        clip: flick.contentWidth > flick.width + 1

        // A plain wheel scrolls the row (a Flickable only takes sideways ones).
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = mt.wheelPx(event, true)
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - d))
            }
        }

        Row {
            id: row
            x: Math.max(0, (flick.width - row.width) / 2)
            y: (flick.height - row.height) / 2
            spacing: 16

            NewTile {}

            // Hidden once the desktop is that look again by other means.
            UndoTile {
                readonly property var prev: DesktopPresetService.previous
                readonly property string last: prev && prev._meta && typeof prev._meta.last === "string"
                    && DesktopPresetService.has(prev._meta.last) ? prev._meta.last : ""
                readonly property bool redo: !!prev && !!prev._meta && prev._meta.undone === true
                visible: !!prev && !DesktopPresetService.isCurrent(prev)
                icon: redo ? "redo" : "undo"
                title: redo ? "REDO" : "UNDO"
                sub: last !== "" ? "back to " + last : "back to the look before"
                onActivated: DesktopPresetService.undoWear()
            }

            UndoTile {
                readonly property var gone: DesktopPresetService.trashed
                visible: !!gone && !DesktopPresetService.has(gone.name)
                icon: "restore_from_trash"
                title: "UNDELETE"
                sub: gone ? gone.name : ""
                onActivated: DesktopPresetService.undoRemove()
            }

            Repeater {
                model: DesktopPresetService.presets

                delegate: PresetTile {
                    required property var modelData

                    entry: modelData
                }
            }

            // Nothing saved yet: say what the first tile is for.
            Item {
                visible: DesktopPresetService.loaded && DesktopPresetService.presets.length === 0
                width: visible ? 190 : 0
                height: root.tileH

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "No presets yet. Set the desktop up the way you like it, then save it here to come back to it later."
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
