import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// What one monitor shows while the screen is locked, dressed like the
// Project Sekai gacha screen: your wallpaper as the "art", a slate side
// panel with a mint selected tab (halftone dots and all), the time as
// big white type with a periwinkle glow, drifting sparkles, and the
// password row at the bottom-right made of the same pills the pull
// buttons are — a white "Password" pill with a dark well (the typed
// dots live there, in the five card-attribute colours), a mint "Unlock"
// pill, and a pink callout bubble that pops up when a try fails.
//
// Pure UI. Lockscreen.qml puts one of these on each screen and they all
// share one LockContext (what's typed, whether PAM is thinking, why the
// last try failed), so typing on one monitor fills the dots on all of
// them. The password field is drawn, not a TextInput: this Item catches
// the keys itself and hands them to the context.
//
// Everything is sized off the screen's height (`u` = 1 at 1080 px tall),
// so it looks the same on a 1080p panel and a 4K one — times the
// monitor's own scale from scale.json (`uiScale`).
Item {
    id: root

    // The shared LockContext.
    required property var context

    // Flip to true for a soft blurred wallpaper instead of the crisp one
    // (the shell's own windows are never visible behind the lock, so the
    // blur is purely a look — it costs a little GPU, which is why the
    // default is off).
    property bool blurWallpaper: SettingsService.flag("lock.blur")

    // The drifting sparkles. They loop forever, which keeps the GPU busy the
    // whole time the screen is locked, so Settings can turn them off.
    readonly property bool animations: SettingsService.flag("lock.animations")

    // This monitor's scale (scale.json / services/ShellScale.qml), handed
    // in by Lockscreen.qml / LockRing.qml. Everything below is sized off
    // `u`, so it is the one place the lockscreen needs to know about it.
    property real uiScale: 1

    // Which monitor this is, so it shows THAT monitor's wallpaper when
    // "One wallpaper per monitor" is on (handed in by Lockscreen.qml /
    // LockRing.qml; "" gives the default wallpaper).
    property string screenName: ""

    // The picture behind everything: the lockscreen's own wallpaper when
    // Settings -> Desktop -> Wallpaper -> Separate Lockscreen Wallpaper is on,
    // else the desktop's (WallpaperService.lockPathFor decides). One place, so
    // the real lock surface and LockRing.qml's copy of it can never differ.
    readonly property string wallpaperFile: WallpaperService.lockImagePathFor(root.screenName)

    readonly property real u: Math.max(0.55, root.height / 1080) * root.uiScale
    function px(n) {
        return Math.round(n * root.u)
    }

    // False while the wallpaper is still being decoded. LockRing.qml waits
    // for it so the ring never runs over a half-loaded picture.
    readonly property bool wallpaperReady: wallpaper.status !== Image.Loading

    readonly property int maxDots: 16
    readonly property bool failed: root.context.failureText !== ""
    // Kept after the failure clears so the bubble can fade out with its
    // words still in it instead of collapsing first.
    property string lastFailure: ""

    focus: true

    // ===== little building blocks =====

    component OutlinedText: Item {
        id: ot
        property string text: ""
        property int pixelSize: 40
        property color color: "white"
        property color outlineColor: LockPalette.periwinkle
        property int outline: 4

        implicitWidth: face.implicitWidth + ot.outline * 2
        implicitHeight: face.implicitHeight + ot.outline * 2

        Repeater {
            model: 14
            delegate: Text {
                required property int index
                x: ot.outline + Math.cos(index * Math.PI / 7) * ot.outline
                y: ot.outline + Math.sin(index * Math.PI / 7) * ot.outline
                text: ot.text
                color: ot.outlineColor
                font.family: Theme.fontFamily
                font.pixelSize: ot.pixelSize
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }

        Text {
            id: face
            x: ot.outline
            y: ot.outline
            text: ot.text
            color: ot.color
            font.family: Theme.fontFamily
            font.pixelSize: ot.pixelSize
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }

    // A four-pointed sparkle that fades and swells in and out, forever.
    component Sparkle: Item {
        id: sp
        property int size: 30
        property int delay: 0
        property color color: "white"

        width: sp.size
        height: sp.size
        opacity: 0
        scale: 0.5

        Shape {
            anchors.fill: parent
            antialiasing: true

            ShapePath {
                fillColor: sp.color
                strokeColor: "transparent"
                strokeWidth: -1
                startX: sp.size / 2
                startY: 0
                PathQuad { x: sp.size; y: sp.size / 2; controlX: sp.size / 2; controlY: sp.size / 2 }
                PathQuad { x: sp.size / 2; y: sp.size; controlX: sp.size / 2; controlY: sp.size / 2 }
                PathQuad { x: 0; y: sp.size / 2; controlX: sp.size / 2; controlY: sp.size / 2 }
                PathQuad { x: sp.size / 2; y: 0; controlX: sp.size / 2; controlY: sp.size / 2 }
            }
        }

        SequentialAnimation {
            running: true

            PauseAnimation { duration: sp.delay }

            SequentialAnimation {
                loops: Animation.Infinite

                ParallelAnimation {
                    NumberAnimation { target: sp; property: "opacity"; to: 0.95; duration: 900; easing.type: Easing.OutQuad }
                    NumberAnimation { target: sp; property: "scale"; to: 1; duration: 900; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    NumberAnimation { target: sp; property: "opacity"; to: 0.05; duration: 1200; easing.type: Easing.InQuad }
                    NumberAnimation { target: sp; property: "scale"; to: 0.4; duration: 1200; easing.type: Easing.InQuad }
                }
                PauseAnimation { duration: 700 }
            }
        }
    }

    // The dots that fade out from the corner of the mint tab.
    component Halftone: Item {
        id: ht
        property int cols: 6
        property int rows: 8
        property int cell: 12
        property color color: "white"

        width: ht.cols * ht.cell + ht.cell / 2
        height: ht.rows * ht.cell

        Repeater {
            model: ht.cols * ht.rows
            delegate: Rectangle {
                required property int index
                readonly property int c: index % ht.cols
                readonly property int r: Math.floor(index / ht.cols)
                // 1 at the top-left corner, fading to 0 towards the far side.
                readonly property real k: 1 - (c + r * 0.55) / ht.cols

                visible: k > 0.12
                width: ht.cell * k * 0.92
                height: width
                radius: width / 2
                x: c * ht.cell + (r % 2) * ht.cell / 2 + (ht.cell - width) / 2
                y: r * ht.cell + (ht.cell - height) / 2
                color: ht.color
                antialiasing: true
            }
        }
    }

    // A row of small dots, like the rules between the side panel's rows.
    component DottedLine: Item {
        id: dl
        property int dot: 4
        property int gap: 6
        property color color: LockPalette.divider

        height: dl.dot

        Row {
            spacing: dl.gap
            Repeater {
                model: Math.max(0, Math.floor((dl.width + dl.gap) / (dl.dot + dl.gap)))
                delegate: Rectangle {
                    width: dl.dot
                    height: dl.dot
                    radius: dl.dot / 2
                    color: dl.color
                }
            }
        }
    }

    // ===== keyboard =====
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.context.tryUnlock()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.context.selectAll()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Delete) {
            if (root.context.allSelected)
                root.context.backspace()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Backspace) {
            // Ctrl+Backspace wipes the lot, plain Backspace takes one off.
            if (event.modifiers & Qt.ControlModifier)
                root.context.clearText()
            else
                root.context.backspace()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Escape
            || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) {
            root.context.clearText()
            event.accepted = true
            return
        }
        // Anything that types a character. Control combinations arrive
        // with a control character as their text (< 32), so this leaves
        // them out; AltGr characters (@, €, ...) come through as normal.
        const t = event.text
        if (t.length > 0 && t.charCodeAt(0) >= 32 && t.charCodeAt(0) !== 127) {
            root.context.typeText(t)
            event.accepted = true
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus()
    }

    // Anywhere you click puts the keyboard back on this monitor.
    MouseArea {
        anchors.fill: parent
        onPressed: root.forceActiveFocus()
    }

    Connections {
        target: root.context
        function onFocusRequested() {
            root.forceActiveFocus()
        }
        function onFailureCountChanged() {
            shakeAnim.restart()
        }
        function onFailureTextChanged() {
            if (root.context.failureText !== "")
                root.lastFailure = root.context.failureText
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Live data for the panel and the corner capsule. Both are passive
    // (UPower / MPRIS — nothing polls), and they only exist while locked.
    BatterySource {
        id: battery
    }

    MediaSource {
        id: media
    }

    // ===== background =====
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: LockPalette.fallbackTop }
            GradientStop { position: 1.0; color: LockPalette.fallbackBottom }
        }
    }

    // The wallpaper, decoded at screen size.
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: !root.blurWallpaper
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, root.width), Math.max(1, root.height))
        source: root.wallpaperFile !== "" ? ("file://" + root.wallpaperFile) : ""
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: root.blurWallpaper && wallpaper.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 40
    }

    // A whisper of slate over the whole picture, and more towards the
    // bottom so the pills always read.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: LockPalette.scrimTop }
            GradientStop { position: 0.5; color: LockPalette.scrimClear }
            GradientStop { position: 1.0; color: LockPalette.scrimBottom }
        }
    }

    // ===== foreground =====
    Item {
        id: content
        anchors.fill: parent

        // Sparkles, scattered by fraction of the screen so they sit in
        // the same places at any size.
        // They animate forever, so they live in a Loader: with
        // "Lockscreen animations" off they are not built at all.
        Loader {
            anchors.fill: parent
            active: root.animations
            sourceComponent: Repeater {
                model: [
                    { fx: 0.19, fy: 0.09, s: 30, d: 0 },
                    { fx: 0.47, fy: 0.06, s: 20, d: 700 },
                    { fx: 0.62, fy: 0.22, s: 44, d: 1300 },
                    { fx: 0.33, fy: 0.46, s: 24, d: 400 },
                    { fx: 0.79, fy: 0.13, s: 26, d: 1900 },
                    { fx: 0.91, fy: 0.42, s: 34, d: 900 },
                    { fx: 0.55, fy: 0.64, s: 22, d: 1600 },
                    { fx: 0.27, fy: 0.70, s: 38, d: 300 },
                    { fx: 0.72, fy: 0.55, s: 18, d: 2200 },
                    { fx: 0.06, fy: 0.90, s: 26, d: 1100 }
                ]

                delegate: Sparkle {
                    required property var modelData
                    required property int index
                    size: root.px(modelData.s)
                    delay: modelData.d
                    x: modelData.fx * content.width
                    y: modelData.fy * content.height
                    color: index % 3 === 0 ? LockPalette.sparkle : "white"
                }
            }
        }

        // ===== side panel =====
        Rectangle {
            id: sidebar
            x: root.px(48)
            y: root.px(130)
            width: root.px(340)
            height: sideCol.implicitHeight + root.px(40)
            radius: root.px(26)
            color: LockPalette.panel
            border.width: 2
            border.color: LockPalette.panelEdge

            Column {
                id: sideCol
                x: root.px(16)
                y: root.px(20)
                width: parent.width - root.px(32)
                spacing: 0

                // The selected tab: you.
                Rectangle {
                    width: parent.width
                    height: root.px(116)
                    radius: root.px(18)
                    color: LockPalette.mint
                    clip: true

                    Halftone {
                        x: root.px(8)
                        y: root.px(6)
                        cols: 6
                        rows: 8
                        cell: root.px(11)
                        color: LockPalette.mintDeep
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: root.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.px(14)

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.px(2)

                            Text {
                                anchors.right: parent.right
                                width: Math.min(implicitWidth, Math.max(root.px(60), sideCol.width - root.px(124)))
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                text: Quickshell.env("USER") || "user"
                                color: LockPalette.cBorder
                                font.family: Theme.fontFamily
                                font.pixelSize: root.px(30)
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                            }
                            Text {
                                anchors.right: parent.right
                                text: "Screen locked"
                                color: Theme.colSubText
                                font.family: Theme.fontFamily
                                font.pixelSize: root.px(19)
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.px(62)
                            height: width
                            radius: width / 2
                            color: "white"
                            antialiasing: true

                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "person"
                                size: root.px(36)
                                fill: 1
                                color: LockPalette.cBorder
                            }
                        }
                    }
                }

                // Rule + what's playing, only when something is. It opens and closes
                // (height, then the opacity of what is in it) instead of popping in
                // and out: before, `visible: media.present` made the panel jump by
                // 126 px the moment a player showed up or went away, and the text
                // blanked a frame before the block was gone. The title and artist
                // shown are the last ones heard, so they stay on screen while the
                // block closes.
                Item {
                    id: mediaBlock
                    width: parent.width
                    height: Math.round(root.px(126) * mediaBlock.reveal)
                    clip: true
                    visible: mediaBlock.reveal > 0.001

                    // 0 -> 1. Starts at the right value, so a player that was
                    // already there when the screen locked is simply there.
                    property real reveal: media.present ? 1 : 0
                    Behavior on reveal {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }

                    property string shownTitle: ""
                    property string shownArtist: ""
                    property bool shownPlaying: false
                    Binding {
                        target: mediaBlock
                        property: "shownTitle"
                        value: media.title
                        when: media.present
                    }
                    Binding {
                        target: mediaBlock
                        property: "shownArtist"
                        value: media.artist
                        when: media.present
                    }
                    Binding {
                        target: mediaBlock
                        property: "shownPlaying"
                        value: media.playing
                        when: media.present
                    }

                    // The content keeps its full size and sits at the top, so it
                    // is uncovered (and covered) rather than squashed; it also
                    // fades a little ahead of the height.
                    Item {
                        width: parent.width
                        height: root.px(126)
                        opacity: Math.max(0, Math.min(1, (mediaBlock.reveal - 0.15) / 0.85))

                        Item {
                            width: parent.width
                            height: root.px(30)

                            DottedLine {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                dot: root.px(4)
                                gap: root.px(7)
                            }
                        }

                        Item {
                            y: root.px(30)
                            width: parent.width
                            height: root.px(96)

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: root.px(14)
                                anchors.right: parent.right
                                anchors.rightMargin: root.px(10)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: root.px(14)

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: mediaBlock.shownPlaying ? "music_note" : "pause"
                                    size: root.px(34)
                                    color: LockPalette.mint
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - root.px(48)
                                    spacing: root.px(2)

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: mediaBlock.shownTitle
                                        color: "white"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.px(23)
                                        font.weight: Font.ExtraBold
                                        font.styleName: Theme.fontStyleBold
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        visible: mediaBlock.shownArtist !== ""
                                        text: mediaBlock.shownArtist
                                        color: LockPalette.lavenderText
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.px(18)
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===== the title =====
        Item {
            id: titleBlock
            x: sidebar.x + sidebar.width + root.px(64)
            y: root.px(34)

            Rectangle {
                id: dateBand
                height: root.px(64)
                width: dateLabel.implicitWidth + root.px(90)
                radius: root.px(12)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: LockPalette.band }
                    GradientStop { position: 0.75; color: LockPalette.band }
                    GradientStop { position: 1.0; color: LockPalette.bandClear }
                }

                Text {
                    id: dateLabel
                    x: root.px(22)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(clock.date, "dddd, MMMM d")
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(38)
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }
            }

            OutlinedText {
                id: bigClock
                y: dateBand.height + root.px(2)
                text: Qt.formatDateTime(clock.date, "hh:mm")
                pixelSize: root.px(236)
                outline: root.px(7)
            }

            // The line of the song that is playing (Settings -> General -> Lyrics on the
            // lockscreen). Nothing is built while it is off.
            Loader {
                id: lyricsLoader
                // (a property of its own, so the capsule's `media` does not read itself)
                property var player: media
                active: SettingsService.flag("lock.lyrics")
                x: root.px(8)
                y: bigClock.y + bigClock.height + root.px(26)

                sourceComponent: LockLyrics {
                    media: lyricsLoader.player
                    px: root.px
                    maxWidth: Math.min(root.px(980), root.width - titleBlock.x - root.px(120))
                }
            }

            // AM / PM, as the mint tag the gacha screen uses for "Group Event Exclusive".
            Rectangle {
                x: bigClock.width + root.px(10)
                y: bigClock.y + bigClock.height * 0.56
                width: ampm.implicitWidth + root.px(44)
                height: root.px(58)
                radius: root.px(14)
                color: LockPalette.mint

                Text {
                    id: ampm
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "AP")
                    color: LockPalette.cBorder
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(36)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }

        // ===== top right =====
        Rectangle {
            id: batteryCap
            visible: battery.available
            anchors.right: parent.right
            anchors.rightMargin: root.px(64)
            y: root.px(40)
            height: root.px(60)
            width: batteryRow.implicitWidth + root.px(48)
            radius: height / 2
            color: LockPalette.cap

            readonly property string glyph: {
                if (battery.isCharging) return "battery_android_frame_bolt"
                if (battery.percentage >= 100) return "battery_android_frame_full"
                const bucket = Math.ceil(battery.percentage / (100 / 6))
                return "battery_android_frame_" + Math.max(1, Math.min(6, bucket))
            }

            Row {
                id: batteryRow
                anchors.centerIn: parent
                spacing: root.px(10)

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: batteryCap.glyph
                    size: root.px(32)
                    color: battery.isLow ? "#ff8a8d" : "white"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: battery.percentage + "%"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(27)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }

        // ===== bottom left =====
        Rectangle {
            x: titleBlock.x
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.px(56)
            height: root.px(58)
            width: lockedRow.implicitWidth + root.px(48)
            radius: height / 2
            color: LockPalette.cap

            Row {
                id: lockedRow
                anchors.centerIn: parent
                spacing: root.px(10)

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lock"
                    size: root.px(26)
                    fill: 1
                    color: LockPalette.mint
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Locked since " + Qt.formatDateTime(LockState.lockedAt, "h:mm AP")
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(24)
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }

        // ===== bottom right: the password row =====
        Item {
            id: controls

            readonly property int pillH: root.px(122)
            readonly property int pwW: root.px(560)
            readonly property int unW: root.px(330)
            readonly property int gap: root.px(26)

            anchors.right: parent.right
            anchors.rightMargin: root.px(84)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.px(52)
            width: pwW + gap + unW
            height: pillH

            // The white "Password" pill (shakes when a try fails).
            Item {
                id: pwGroup
                width: controls.pwW
                height: controls.pillH
                transform: Translate { id: shake; x: 0 }

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: shake; property: "x"; to: -root.px(16); duration: 55 }
                    NumberAnimation { target: shake; property: "x"; to: root.px(14); duration: 70 }
                    NumberAnimation { target: shake; property: "x"; to: -root.px(9); duration: 70 }
                    NumberAnimation { target: shake; property: "x"; to: root.px(5); duration: 60 }
                    NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
                }

                Rectangle {
                    y: root.px(6)
                    width: parent.width
                    height: parent.height
                    radius: height * 0.42
                    color: LockPalette.shadow
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height * 0.42
                    color: LockPalette.paper
                    border.width: root.failed ? root.px(4) : 0
                    border.color: LockPalette.pink

                    Behavior on border.width {
                        NumberAnimation { duration: 120 }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Leaves the same room on both sides for the layout tag, so the
                        // text stays centred.
                        width: parent.width - 2 * (layoutTag.visible ? layoutTag.width + root.px(28) : root.px(24))
                        y: root.px(12)
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: root.context.fprintListening ? root.context.fprintMessage
                              : (root.context.unlockInProgress ? "Checking…" : "Password")
                        color: root.context.fprintMessageIsError ? LockPalette.pink : LockPalette.cBorder
                        font.family: Theme.fontFamily
                        font.pixelSize: root.px(34)
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                    }

                    // The keyboard layout, a tag on the corner like the Unlock pill's "Enter".
                    LockLayoutTag {
                        id: layoutTag
                        x: parent.width - width - root.px(14)
                        y: root.px(8)
                        fillColor: LockPalette.mint
                        textColor: LockPalette.cBorder
                        fontPixelSize: root.px(18)
                        tagHeight: root.px(30)
                        sidePadding: root.px(26)
                    }

                    // The dark well: the typed dots sit in here.
                    Rectangle {
                        id: well
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.px(14)
                        width: parent.width - root.px(64)
                        height: root.px(48)
                        radius: height / 2
                        color: LockPalette.well

                        // Ctrl+A: the selection behind the dots.
                        Rectangle {
                            anchors.centerIn: dots
                            width: dots.width + root.px(24)
                            height: root.px(34)
                            radius: height / 2
                            color: Qt.rgba(0.30, 0.82, 1, 0.45)
                            border.width: root.px(2)
                            border.color: Qt.rgba(1, 1, 1, 0.8)
                            visible: root.context.allSelected && dots.shown > 0
                        }

                        Row {
                            id: dots
                            anchors.centerIn: parent
                            spacing: root.px(9)
                            opacity: root.context.unlockInProgress ? 0.45 : 1

                            readonly property int shown: Math.min(root.context.currentText.length, root.maxDots)

                            Behavior on opacity {
                                NumberAnimation { duration: 120 }
                            }

                            Repeater {
                                model: dots.shown

                                delegate: Rectangle {
                                    required property int index

                                    width: root.px(22)
                                    height: width
                                    radius: width / 2
                                    antialiasing: true
                                    // Colour follows the character's place in the
                                    // password, so it doesn't flicker as the row
                                    // stops growing past maxDots.
                                    color: Theme.attributeColors[(root.context.currentText.length - dots.shown + index) % Theme.attributeColors.length]

                                    // Pops in when typed.
                                    NumberAnimation on scale {
                                        from: 0.3
                                        to: 1
                                        duration: 150
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 2.5
                                    }
                                }
                            }
                        }
                    }
                }

                // The pink callout: why the last try failed.
                Item {
                    id: bubble
                    x: root.px(34)
                    y: -height - root.px(18)
                    width: Math.min(bubbleText.implicitWidth + root.px(52), root.px(640))
                    height: root.px(58)
                    opacity: root.failed ? 1 : 0
                    scale: root.failed ? 1 : 0.85
                    transformOrigin: Item.BottomLeft

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.px(14)
                        color: LockPalette.pink
                    }

                    // The little tail, pointing down at the pill.
                    Rectangle {
                        x: root.px(40)
                        y: parent.height - root.px(13)
                        width: root.px(24)
                        height: width
                        rotation: 45
                        color: LockPalette.pink
                    }

                    Text {
                        id: bubbleText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, bubble.width - root.px(52))
                        elide: Text.ElideRight
                        text: root.lastFailure
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: root.px(26)
                        font.weight: Font.Bold
                        font.styleName: Theme.fontStyleBold
                    }
                }
            }

            // The mint "Unlock" pill.
            Item {
                id: unlockPill
                x: controls.pwW + controls.gap
                width: controls.unW
                height: controls.pillH
                scale: unlockArea.pressed ? 0.97 : 1

                Behavior on scale {
                    NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                }

                Rectangle {
                    y: root.px(6)
                    width: parent.width
                    height: parent.height
                    radius: height * 0.42
                    color: LockPalette.shadow
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height * 0.42
                    color: LockPalette.mint

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: root.px(30)
                        y: root.px(12)
                        text: "Unlock"
                        color: LockPalette.cBorder
                        font.family: Theme.fontFamily
                        font.pixelSize: root.px(34)
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.px(14)
                        width: parent.width - root.px(64)
                        height: root.px(48)
                        radius: height / 2
                        color: LockPalette.well

                        Row {
                            anchors.centerIn: parent
                            visible: !root.context.unlockInProgress
                            spacing: root.px(10)

                            // Shown alongside the arrow after PAM reports a fingerprint prompt.
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.context.fprintListening
                                name: "fingerprint"
                                size: root.px(26)
                                weight: 600
                                color: root.failed ? LockPalette.pink : LockPalette.mint

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }
                            }

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "arrow_forward"
                                size: root.px(28)
                                weight: 600
                                color: LockPalette.mint
                            }
                        }

                        MaterialIcon {
                            id: spinner
                            anchors.centerIn: parent
                            visible: root.context.unlockInProgress
                            name: "progress_activity"
                            size: root.px(28)
                            weight: 600
                            color: LockPalette.mint

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                                running: spinner.visible
                            }
                        }
                    }
                }

                // The little pink tag on the corner, like "Once daily".
                Rectangle {
                    x: root.px(14)
                    y: root.px(8)
                    width: hint.implicitWidth + root.px(26)
                    height: root.px(30)
                    radius: height / 2
                    color: LockPalette.pink

                    Text {
                        id: hint
                        anchors.centerIn: parent
                        text: "Enter"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: root.px(18)
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                    }
                }

                MouseArea {
                    id: unlockArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.forceActiveFocus()
                        root.context.tryUnlock()
                    }
                }
            }
        }
    }
}
