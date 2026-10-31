import Quickshell
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCrop.js" as LC

// The Calendar lockscreen: what one monitor shows while the screen is locked, as a
// printed poster built from the shell's own blocks (LockPlate.qml: outline, white ring,
// hard shadow straight down), in your theme's colours. Three straight-sided frames cut
// out of YOUR wallpaper in colour (a wide one, a tall one, a small one), each on a
// hard shadow of one of the theme's inks; the clock as four keycaps in a shallow V
// (hours dark, minutes mint, two diamonds between them, like the desktop clock widget's
// Keys design) under a date sticker; and along the bottom a calendar card with every
// day of the month in two rows, the password plate (dots in the five card-attribute
// colours), an Enter key and round Restart / Shut down keys.
//
// Hold Ctrl and the Enter key turns into a coffee key: Ctrl+Enter (or a click, or a
// right click on it) puts the machine to sleep instead of unlocking. The screen stays
// locked, so it wakes up here.
//
// Same job and same interface as LockSurface.qml (the Project Sekai gacha look);
// LockHost.qml picks between them by Settings -> General -> Launcher & lock ->
// Lockscreen style. Pure UI: the password, Ctrl state and the power actions are in
// LockContext.qml, shared by every monitor.
//
// WHICH PART of the wallpaper each frame shows: the frames' places are fixed (fractions
// of the screen, below). Their pictures are chosen from a tiny copy of the wallpaper
// (services/LockCropService.qml, modules/common/functions/LockCrop.js): the most
// interesting part for the wide frame, then the best part that is left for the tall
// one, then another for the close-up. Settings -> ... -> Picture crops: Fixed skips
// that and always shows the same three spots. Without ImageMagick it falls back to
// Fixed by itself.
//
// Laid out in fractions of the screen and sized off its height (`u` = 1 at 1080 px
// tall), so it fills any monitor like a poster. The shell scale (`uiScale`) is
// deliberately not applied: scaling a poster only makes it overflow its frames.
//
// Nothing here animates by itself: it is drawn once a minute, so a locked screen costs
// the GPU nothing in between.
Item {
    id: root

    // The shared LockContext.
    required property var context

    // Accepted so LockHost can hand every look the same things; not used (see above).
    property real uiScale: 1

    // Which monitor this is, so it shows THAT monitor's wallpaper when "One wallpaper
    // per monitor" is on.
    property string screenName: ""

    // The same picture LockSurface.qml shows (WallpaperService decides which).
    readonly property string wallpaperFile: WallpaperService.lockImagePathFor(root.screenName)

    readonly property real u: Math.max(0.55, root.height / 1080)
    function px(n) {
        return Math.round(n * root.u)
    }

    // False while the wallpaper is still being decoded or its crops are still being
    // worked out. LockRing.qml waits for it so the ring never runs over a half-made
    // picture.
    readonly property bool wallpaperReady: wallpaper.status !== Image.Loading
        && (!root.autoCrop || LockCropService.settled(root.wallpaperFile))

    // ===== colours =====
    // The shell's blocks: outline, shadow and text are the border colour; plates are the
    // lockscreen's white; three inks from the theme's accents; a pale themed sheet.
    readonly property color ink: LockPalette.cBorder
    readonly property color white: LockPalette.paper
    readonly property color paper: LockPalette.calPaper
    readonly property color accent: LockPalette.calAccent
    readonly property color mint: LockPalette.calMint
    readonly property color lilac: LockPalette.calLilac

    // Pictures in colour (default) or the earlier black and white.
    readonly property bool mono: SettingsService.get("lock.tone") === "mono"

    // How the blocks are cut: a plate's outline, its white ring, how far its hard shadow
    // drops (the frames' drops further), and how round the frames' corners are.
    readonly property int outlineW: root.px(3)
    readonly property int ringW: root.px(2)
    readonly property int shadowSmall: root.px(6)
    readonly property int shadowFrame: root.px(12)
    readonly property int frameRadius: root.px(18)

    readonly property int maxDots: 16
    readonly property bool failed: root.context.failureText !== ""
    // Kept after the failure clears so the field's label does not blank first.
    property string lastFailure: ""

    focus: true

    // ===== the wallpaper, and which parts of it the frames show =====
    readonly property bool autoCrop: SettingsService.get("lock.crop") !== "fixed"

    // Decoded once, a little bigger than the screen, so a close-up of a part of it
    // still has detail. (The frames load the same file at the same size and share it.)
    readonly property int decodeSide: Math.min(3200, Math.max(1280, Math.ceil(Math.max(root.width, root.height) * 1.5)))
    readonly property string imageUrl: root.wallpaperFile !== "" ? ("file://" + root.wallpaperFile) : ""

    Image {
        id: wallpaper
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(root.decodeSide, root.decodeSide)
        source: root.imageUrl
    }

    readonly property real imageAspect: wallpaper.implicitWidth > 0 && wallpaper.implicitHeight > 0
        ? wallpaper.implicitWidth / wallpaper.implicitHeight
        : (root.grid ? root.grid.w / root.grid.h : 16 / 9)

    readonly property var grid: root.autoCrop ? LockCropService.gridFor(root.wallpaperFile) : null

    function askCrop() {
        if (root.autoCrop && root.wallpaperFile !== "")
            LockCropService.request(root.wallpaperFile)
    }
    onWallpaperFileChanged: root.askCrop()
    onAutoCropChanged: root.askCrop()

    // The three frames, as fractions of the screen (x, y, width, height). A wide one
    // top left, a tall one on the right, a small one under the wide one.
    readonly property rect rectA: Qt.rect(Math.round(0.021 * root.width), Math.round(0.040 * root.height),
                                          Math.round(0.679 * root.width), Math.round(0.441 * root.height))
    readonly property rect rectB: Qt.rect(Math.round(0.718 * root.width), Math.round(0.040 * root.height),
                                          Math.round(0.261 * root.width), Math.round(0.745 * root.height))
    readonly property rect rectC: Qt.rect(Math.round(0.427 * root.width), Math.round(0.519 * root.height),
                                          Math.round(0.273 * root.width), Math.round(0.269 * root.height))

    readonly property var specs: LC.specsFor([
        root.rectA.width / Math.max(1, root.rectA.height),
        root.rectB.width / Math.max(1, root.rectB.height),
        root.rectC.width / Math.max(1, root.rectC.height)
    ])
    readonly property var windows: root.grid ? LC.plan(root.grid, root.specs)
                                             : LC.fixedPlan(root.imageAspect, root.specs)

    // ===== the clock, the month =====
    readonly property bool use24h: SettingsService.flag("time.use24h")
    readonly property string timeText: root.use24h ? Qt.formatDateTime(clock.date, "HH:mm")
                                                   : Qt.formatDateTime(clock.date, "hh:mm AP").split(" ")[0]
    readonly property string ampmText: root.use24h ? "" : Qt.formatDateTime(clock.date, "AP")

    // Only the year, month and day are read off the clock, so the list of days below
    // is rebuilt when the MONTH changes, not every minute.
    readonly property int yearNow: clock.date.getFullYear()
    readonly property int monthNow: clock.date.getMonth()
    readonly property int dayNow: clock.date.getDate()
    readonly property int weekdayNow: clock.date.getDay()

    readonly property var dayNames: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    readonly property var monthNames: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    readonly property var monthDays: {
        const y = root.yearNow, m = root.monthNow
        const n = new Date(y, m + 1, 0).getDate()
        const out = []
        for (let d = 1; d <= n; d++) {
            const wd = new Date(y, m, d).getDay()
            out.push({ day: d, wd: wd, weekend: wd === 0 || wd === 6 })
        }
        return out
    }
    readonly property int calCols: Math.ceil(root.monthDays.length / 2)

    // ===== geometry shared by the pieces =====
    // The bottom row (calendar, password, keys) starts at barTop + a little.
    readonly property int barTop: root.height - Math.round(root.height * 0.17)
    readonly property int rowY: root.barTop + root.px(28)
    readonly property int rowH: root.px(100)
    // The left column, between the wide frame and the bottom row, left of the small frame.
    readonly property int colX: root.rectA.x
    readonly property int colRight: Math.round(root.rectC.x) - root.px(30)
    readonly property int colTop: Math.round(root.rectA.y + root.rectA.height) + root.px(34)
    readonly property int colBottom: Math.round(root.rectC.y + root.rectC.height)

    // ===== keyboard =====
    Keys.onPressed: event => {
        root.context.ctrlHeld = event.key === Qt.Key_Control || (event.modifiers & Qt.ControlModifier) !== 0
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier)
                root.context.sleep()
            else
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
        // Anything that types a character. Control combinations arrive with a control
        // character as their text (< 32), so this leaves them out; AltGr characters
        // (@, €, ...) come through as normal.
        const t = event.text
        if (t.length > 0 && t.charCodeAt(0) >= 32 && t.charCodeAt(0) !== 127) {
            root.context.typeText(t)
            event.accepted = true
        }
    }

    Keys.onReleased: event => {
        // On the release of Ctrl itself the modifier is already gone from the event
        // (or not, depending on the platform): the key says it either way.
        root.context.ctrlHeld = event.key !== Qt.Key_Control && (event.modifiers & Qt.ControlModifier) !== 0
    }

    // Losing the keyboard (another monitor took it) must not leave the coffee key stuck.
    onActiveFocusChanged: {
        if (!root.activeFocus)
            root.context.ctrlHeld = false
    }

    Component.onCompleted: {
        root.askCrop()
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

    // Live data for the footer and the caption. Both are passive (UPower / MPRIS,
    // nothing polls), and they only exist while locked.
    BatterySource {
        id: battery
    }

    MediaSource {
        id: media
    }

    // ===== the sheet =====
    Rectangle {
        anchors.fill: parent
        color: root.paper
    }

    // A faint halftone over the whole sheet, like printed paper.
    Item {
        anchors.fill: parent
        clip: true
        opacity: 0.08

        Item {
            readonly property int k: Math.max(1, Math.round(root.u))
            width: parent.width / k
            height: parent.height / k
            scale: k
            transformOrigin: Item.TopLeft

            Image {
                anchors.fill: parent
                source: "file://" + Directories.asset("images/lock-dots.png")
                fillMode: Image.Tile
                smooth: false
            }
        }
    }

    // ===== the three frames =====
    // Plain rectangles with softly rounded corners, each on a hard shadow that drops
    // straight down in one of the theme's inks (the border colour in black and white).
    LockPanel {
        x: root.rectA.x
        y: root.rectA.y
        width: root.rectA.width
        height: root.rectA.height
        source: root.imageUrl
        sourceSize: Qt.size(root.decodeSide, root.decodeSide)
        imageAspect: root.imageAspect
        win: root.windows[0]
        mono: root.mono
        ink: root.ink
        ringColor: root.white
        shadowColor: root.mono ? root.ink : root.accent
        outline: root.px(4)
        ringWidth: root.px(3)
        shadowDy: root.shadowFrame
        cornerRadius: root.frameRadius
        dotStrength: root.mono ? 0.55 : 0.2
        dotScale: Math.max(1, Math.round(root.u))
    }

    LockPanel {
        x: root.rectB.x
        y: root.rectB.y
        width: root.rectB.width
        height: root.rectB.height
        source: root.imageUrl
        sourceSize: Qt.size(root.decodeSide, root.decodeSide)
        imageAspect: root.imageAspect
        win: root.windows[1]
        mono: root.mono
        ink: root.ink
        ringColor: root.white
        shadowColor: root.mono ? root.ink : root.mint
        outline: root.px(4)
        ringWidth: root.px(3)
        shadowDy: root.shadowFrame
        cornerRadius: root.frameRadius
        dotStrength: root.mono ? 0.55 : 0.2
        dotScale: Math.max(1, Math.round(root.u))
    }

    LockPanel {
        x: root.rectC.x
        y: root.rectC.y
        width: root.rectC.width
        height: root.rectC.height
        source: root.imageUrl
        sourceSize: Qt.size(root.decodeSide, root.decodeSide)
        imageAspect: root.imageAspect
        win: root.windows[2]
        mono: root.mono
        tinted: true
        tint: root.accent
        ink: root.ink
        ringColor: root.white
        shadowColor: root.mono ? root.ink : root.lilac
        outline: root.px(4)
        ringWidth: root.px(3)
        shadowDy: root.shadowFrame
        cornerRadius: root.frameRadius
        dotStrength: root.mono ? 0.55 : 0.2
        dotScale: Math.max(1, Math.round(root.u))
    }

    // What is playing: a small plate on the corner of the wide frame. It fades in and
    // out; the title and artist shown are the last ones heard, so they stay while it
    // fades.
    Item {
        id: caption
        x: root.rectA.x + root.px(26)
        y: root.rectA.y + root.rectA.height - height - root.px(30)
        width: Math.min(captionRow.implicitWidth + root.px(44), root.px(620))
        height: root.px(50)
        opacity: media.present ? 1 : 0
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        property string shownTitle: ""
        property string shownArtist: ""
        property bool shownPlaying: false
        Binding { target: caption; property: "shownTitle"; value: media.title; when: media.present }
        Binding { target: caption; property: "shownArtist"; value: media.artist; when: media.present }
        Binding { target: caption; property: "shownPlaying"; value: media.playing; when: media.present }

        LockPlate {
            anchors.fill: parent
            fillColor: root.white
            outlineColor: root.ink
            ringColor: root.white
            shadowColor: root.ink
            outline: root.outlineW
            ring: root.ringW
            shadowDy: root.shadowSmall

            Row {
                id: captionRow
                anchors.centerIn: parent
                spacing: root.px(10)

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: caption.shownPlaying ? "music_note" : "pause"
                    size: root.px(26)
                    color: root.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.px(620) - root.px(150))
                    elide: Text.ElideRight
                    text: caption.shownTitle
                    color: root.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(20)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: caption.shownArtist !== ""
                    text: caption.shownArtist
                    color: LockPalette.calMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(16)
                    font.weight: Font.Bold
                }
            }
        }
    }

    // ===== left column: who, when, and the time as four keys =====

    // "LOCKED", a mint chip.
    LockPlate {
        id: lockedTag
        x: root.colX
        y: root.colTop
        width: lockedRow.implicitWidth + root.px(40)
        height: root.px(46)
        fillColor: root.mint
        outlineColor: root.ink
        ringColor: root.white
        shadowColor: root.ink
        outline: root.outlineW
        ring: root.ringW
        shadowDy: root.shadowSmall

        Row {
            id: lockedRow
            anchors.centerIn: parent
            spacing: root.px(8)

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: root.px(24)
                fill: 1
                color: root.ink
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "LOCKED"
                color: root.ink
                font.family: Theme.fontFamily
                font.pixelSize: root.px(22)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
                font.letterSpacing: root.px(1)
            }
        }
    }

    // The name tag: a dark "NAME" chip and your user name, on a white plate.
    LockPlate {
        id: nameTag
        x: lockedTag.x + lockedTag.width + root.px(16)
        y: root.colTop
        width: Math.min(nameRow.implicitWidth + root.px(36), Math.max(root.px(160), root.colRight - nameTag.x))
        height: root.px(46)
        fillColor: root.white
        outlineColor: root.ink
        ringColor: root.white
        shadowColor: root.ink
        outline: root.outlineW
        ring: root.ringW
        shadowDy: root.shadowSmall

        Row {
            id: nameRow
            anchors.centerIn: parent
            spacing: root.px(10)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: nameLabel.implicitWidth + root.px(20)
                height: root.px(26)
                radius: height / 2
                color: root.ink

                Text {
                    id: nameLabel
                    anchors.centerIn: parent
                    text: "NAME"
                    color: root.white
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(14)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    font.letterSpacing: root.px(1)
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(root.px(60), root.colRight - nameTag.x - root.px(150)))
                elide: Text.ElideRight
                text: (Quickshell.env("USER") || "user").toUpperCase()
                color: root.ink
                font.family: Theme.fontFamily
                font.pixelSize: root.px(24)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }
    }

    // The date, as a sticker: a pink diamond and the day, date and month.
    LockPlate {
        id: datePlate
        x: root.colX
        y: root.colTop + root.px(62)
        width: dateRow.implicitWidth + root.px(40)
        height: root.px(46)
        fillColor: root.white
        outlineColor: root.ink
        ringColor: root.white
        shadowColor: root.ink
        outline: root.outlineW
        ring: root.ringW
        shadowDy: root.shadowSmall

        Row {
            id: dateRow
            anchors.centerIn: parent
            spacing: root.px(12)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.px(14)
                height: width
                rotation: 45
                color: root.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.dayNames[root.weekdayNow] + "  " + root.dayNow + "  " + root.monthNames[root.monthNow]
                color: root.ink
                font.family: Theme.fontFamily
                font.pixelSize: root.px(24)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
                font.letterSpacing: root.px(1)
            }
        }
    }

    // AM / PM, a little pink chip beside the date (12-hour clocks only).
    LockPlate {
        visible: root.ampmText !== ""
        x: datePlate.x + datePlate.width + root.px(16)
        y: datePlate.y
        width: ampmLabel.implicitWidth + root.px(36)
        height: root.px(46)
        fillColor: root.accent
        outlineColor: root.ink
        ringColor: root.white
        shadowColor: root.ink
        outline: root.outlineW
        ring: root.ringW
        shadowDy: root.shadowSmall

        Text {
            id: ampmLabel
            anchors.centerIn: parent
            text: root.ampmText
            color: root.ink
            font.family: Theme.fontFamily
            font.pixelSize: root.px(22)
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }

    // The time: four keys in a shallow V (the inner two sit lower), the hours dark and
    // the minutes mint fading to cyan, with two diamonds in the gap. The same four
    // keys as the desktop clock's Keys design, in the lockscreen's colours.
    readonly property var timeDigits: {
        const p = root.timeText.split(":")
        if (p.length < 2 || p[0].length < 2 || p[1].length < 2)
            return ["0", "0", "0", "0"]
        return [p[0][0], p[0][1], p[1][0], p[1][1]]
    }

    Item {
        id: clockKeys
        x: root.colX
        y: root.colTop + root.px(124)
        width: root.colRight - root.colX
        height: root.colBottom - y

        readonly property real gap: root.px(14)
        readonly property real mid: root.px(64)
        readonly property real stagger: root.px(16)
        readonly property real keyW: Math.min(root.px(150), (width - 2 * gap - mid) / 4)
        readonly property real keyH: Math.max(root.px(60), height - stagger - root.shadowSmall - root.px(4))
        readonly property real startX: (width - (4 * keyW + 2 * gap + mid)) / 2

        Repeater {
            model: root.timeDigits

            delegate: LockPlate {
                id: keyPlate

                required property int index
                required property string modelData

                readonly property bool hours: keyPlate.index < 2

                x: Math.round(clockKeys.startX + (keyPlate.index < 2
                    ? keyPlate.index * (clockKeys.keyW + clockKeys.gap)
                    : 2 * clockKeys.keyW + clockKeys.gap + clockKeys.mid + (keyPlate.index - 2) * (clockKeys.keyW + clockKeys.gap)))
                y: (keyPlate.index === 1 || keyPlate.index === 2) ? clockKeys.stagger : 0
                width: Math.round(clockKeys.keyW)
                height: Math.round(clockKeys.keyH)
                cornerRadius: root.px(22)
                fillColor: keyPlate.hours ? root.ink : root.mint
                fillBottom: keyPlate.hours ? "transparent"
                            : LockPalette.hsl(LockPalette.hue(LockPalette.cA), 0.8, 0.72)
                outlineColor: root.ink
                ringColor: root.white
                shadowColor: root.ink
                outline: root.px(4)
                ring: root.px(3)
                shadowDy: root.px(8)

                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: keyPlate.modelData
                    color: keyPlate.hours ? root.white : root.ink
                    fontSizeMode: Text.Fit
                    minimumPixelSize: root.px(40)
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(128)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }

        // The two diamonds, one above the other, in the gap between the hours and minutes.
        Rectangle {
            x: Math.round(clockKeys.startX + 2 * clockKeys.keyW + clockKeys.gap + (clockKeys.mid - width) / 2)
            y: Math.round(clockKeys.height * 0.3 - height / 2)
            width: root.px(26)
            height: width
            rotation: 45
            radius: root.px(5)
            color: root.accent
            border.width: root.outlineW
            border.color: root.ink
        }

        Rectangle {
            x: Math.round(clockKeys.startX + 2 * clockKeys.keyW + clockKeys.gap + (clockKeys.mid - width) / 2)
            y: Math.round(clockKeys.height * 0.62 - height / 2)
            width: root.px(26)
            height: width
            rotation: 45
            radius: root.px(5)
            color: root.mint
            border.width: root.outlineW
            border.color: root.ink
        }
    }

    // ===== the small print, right under the tall frame =====
    Item {
        id: footer
        x: root.rectB.x + root.rectB.width - width
        y: root.rectB.y + root.rectB.height + root.shadowFrame + root.px(12)
        width: footerText.implicitWidth + root.px(40)
        height: root.px(34)

        LockPlate {
            anchors.fill: parent
            fillColor: battery.available && battery.isLow ? root.accent : root.white
            outlineColor: root.ink
            ringColor: root.white
            shadowColor: root.ink
            outline: root.px(2)
            ring: root.px(2)
            shadowDy: root.px(4)

            Text {
                id: footerText
                anchors.centerIn: parent
                text: "LOCKED SINCE " + Qt.formatDateTime(LockState.lockedAt, "h:mm AP").toUpperCase()
                      + (battery.available ? "  \u00b7  " + battery.percentage + "%" + (battery.isCharging ? " +" : "") : "")
                color: root.ink
                font.family: Theme.fontFamily
                font.pixelSize: root.px(14)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
                font.letterSpacing: root.px(1)
            }
        }
    }

    // ===== the bottom row: the month, the password, Enter, Restart, Shut down =====

    // The month as a card: every day, in two rows. Weekends in pink, today a mint key.
    readonly property real calLeft: root.colX
    readonly property real calRight: controls.x - root.px(36)
    readonly property real calPad: root.px(10)
    readonly property real cellW: Math.min(root.px(64), (root.calRight - root.calLeft - 2 * (root.outlineW + root.ringW) - 2 * root.calPad) / Math.max(1, root.calCols))
    // Too narrow for the numbers (a very tall or small screen): leave the month out.
    readonly property bool showMonth: root.cellW >= root.px(28)

    LockPlate {
        id: calCard
        visible: root.showMonth
        x: root.calLeft
        y: root.rowY
        width: root.calRight - root.calLeft
        height: root.rowH
        cornerRadius: root.px(26)
        fillColor: root.white
        outlineColor: root.ink
        ringColor: root.white
        shadowColor: root.ink
        outline: root.outlineW
        ring: root.ringW
        shadowDy: root.shadowSmall

        Item {
            anchors.centerIn: parent
            width: root.cellW * root.calCols
            height: parent.height - 2 * root.px(6)

            Repeater {
                model: root.showMonth ? root.monthDays : []

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    readonly property bool isToday: cell.modelData.day === root.dayNow
                    readonly property int row: cell.index < root.calCols ? 0 : 1
                    readonly property int col: cell.index < root.calCols ? cell.index : cell.index - root.calCols

                    x: cell.col * root.cellW
                    y: cell.row * (parent.height / 2)
                    width: root.cellW
                    height: parent.height / 2

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.px(2)
                        radius: root.px(11)
                        color: root.mint
                        border.width: root.px(2)
                        border.color: root.ink
                        visible: cell.isToday
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.dayNames[cell.modelData.wd]
                            color: cell.isToday ? root.ink : (cell.modelData.weekend ? root.accent : LockPalette.calMuted)
                            font.family: Theme.fontFamily
                            font.pixelSize: root.px(11)
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (cell.modelData.day < 10 ? "0" : "") + cell.modelData.day
                            color: cell.isToday ? root.ink : (cell.modelData.weekend ? root.accent : root.ink)
                            font.family: Theme.fontFamily
                            font.pixelSize: root.px(20)
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }
                    }
                }
            }
        }
    }

    Item {
        id: controls

        readonly property int keyH: root.rowH
        readonly property int gap: root.px(16)
        readonly property int fieldW: Math.round(Math.max(root.px(260), Math.min(root.px(380), root.width * 0.2)))
        readonly property int enterW: root.px(150)
        readonly property int roundD: root.px(92)
        readonly property bool power: SettingsService.flag("lock.powerButtons")

        width: fieldW + gap + enterW + (power ? 2 * (gap + roundD) : 0)
        height: keyH
        x: root.width - root.px(44) - width
        y: root.rowY

        // ----- the password plate (shakes when a try fails) -----
        Item {
            id: pwGroup
            width: controls.fieldW
            height: controls.keyH
            transform: Translate { id: shake; x: 0 }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: -root.px(16); duration: 55 }
                NumberAnimation { target: shake; property: "x"; to: root.px(14); duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: -root.px(9); duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: root.px(5); duration: 60 }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
            }

            LockPlate {
                anchors.fill: parent
                cornerRadius: root.px(26)
                fillColor: root.white
                outlineColor: root.failed ? root.accent : root.ink
                ringColor: root.white
                shadowColor: root.failed ? root.accent : root.ink
                outline: root.outlineW
                ring: root.ringW
                shadowDy: root.shadowSmall

                Behavior on outlineColor {
                    ColorAnimation { duration: 120 }
                }

                Row {
                    x: root.px(20)
                    y: root.px(10)
                    width: parent.width - root.px(40) - (calLayoutTag.visible ? calLayoutTag.width + root.px(8) : 0)
                    spacing: root.px(6)

                    // Shown after PAM reports a fingerprint prompt.
                    MaterialIcon {
                        id: calFpIcon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.context.fprintListening
                        name: "fingerprint"
                        size: root.px(16)
                        color: root.failed ? root.accent : root.mint

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (calFpIcon.visible ? calFpIcon.width + parent.spacing : 0)
                        elide: Text.ElideRight
                        text: root.failed ? root.lastFailure.toUpperCase()
                            : (root.context.fprintListening ? root.context.fprintMessage.toUpperCase()
                            : (root.context.unlockInProgress ? "CHECKING\u2026" : "PASSWORD"))
                        color: root.failed || root.context.fprintMessageIsError ? root.accent : LockPalette.calMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.px(14)
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                        font.letterSpacing: root.px(1)
                    }
                }

                // The keyboard layout you are typing in, at the end of the label's line.
                LockLayoutTag {
                    id: calLayoutTag
                    x: parent.width - width - root.px(20)
                    y: root.px(8)
                    fillColor: root.ink
                    textColor: root.white
                    fontPixelSize: root.px(12)
                    tagHeight: root.px(22)
                    sidePadding: root.px(16)
                    onActivated: root.forceActiveFocus()
                }

                // The dots sit in a pale well.
                Rectangle {
                    id: well
                    x: root.px(12)
                    y: parent.height - height - root.px(10)
                    width: parent.width - root.px(24)
                    height: root.px(40)
                    radius: height / 2
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1)

                    // Ctrl+A: the selection behind the dots.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: dots.x - root.px(8)
                        width: dots.width + root.px(16)
                        height: root.px(30)
                        radius: height / 2
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                        visible: root.context.allSelected && dots.shown > 0
                    }

                    Row {
                        id: dots
                        x: root.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.px(7)
                        opacity: root.context.unlockInProgress ? 0.45 : 1

                        readonly property int dotSize: root.px(20)
                        readonly property int fits: Math.max(1, Math.floor((well.width - root.px(32) + spacing) / (dotSize + spacing)))
                        readonly property int shown: Math.min(root.context.currentText.length, Math.min(root.maxDots, fits))

                        Behavior on opacity {
                            NumberAnimation { duration: 120 }
                        }

                        Repeater {
                            model: dots.shown

                            delegate: Rectangle {
                                required property int index

                                width: dots.dotSize
                                height: width
                                radius: width / 2
                                antialiasing: true
                                border.width: root.px(2)
                                border.color: root.ink
                                // Colour follows the character's place in the password,
                                // so it doesn't flicker as the row stops growing.
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
        }

        // ----- Enter; with Ctrl held it is the coffee (sleep) key -----
        Item {
            id: enterKey
            x: controls.fieldW + controls.gap
            width: controls.enterW
            height: controls.keyH

            readonly property bool coffee: root.context.ctrlHeld

            LockPlate {
                anchors.fill: parent
                cornerRadius: root.px(26)
                pressed: enterArea.pressed
                fillColor: enterKey.coffee ? root.accent : root.mint
                outlineColor: root.ink
                ringColor: root.white
                shadowColor: root.ink
                outline: root.outlineW
                ring: root.ringW
                shadowDy: root.shadowSmall

                Behavior on fillColor {
                    ColorAnimation { duration: 120 }
                }

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.px(8)
                    visible: opacity > 0.01
                    opacity: enterKey.coffee || root.context.unlockInProgress ? 0 : 1
                    name: "keyboard_return"
                    size: root.px(38)
                    weight: 600
                    color: root.ink

                    Behavior on opacity {
                        NumberAnimation { duration: 110 }
                    }
                }

                MaterialIcon {
                    id: spinner
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.px(8)
                    visible: root.context.unlockInProgress && !enterKey.coffee
                    name: "progress_activity"
                    size: root.px(38)
                    weight: 600
                    color: root.ink

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: spinner.visible
                    }
                }

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.px(8)
                    visible: opacity > 0.01
                    opacity: enterKey.coffee ? 1 : 0
                    scale: enterKey.coffee ? 1 : 0.6
                    name: "coffee"
                    size: root.px(38)
                    fill: 1
                    color: root.ink

                    Behavior on opacity {
                        NumberAnimation { duration: 110 }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - height - root.px(8)
                    text: enterKey.coffee ? "SLEEP" : "ENTER"
                    color: root.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(16)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    font.letterSpacing: root.px(1)
                }
            }

            MouseArea {
                id: enterArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    root.forceActiveFocus()
                    if (enterKey.coffee || mouse.button === Qt.RightButton)
                        root.context.sleep()
                    else
                        root.context.tryUnlock()
                }
            }
        }

        // ----- Restart and Shut down: round keys (press twice) -----
        LockPowerKey {
            id: restartKey
            visible: controls.power
            x: enterKey.x + controls.enterW + controls.gap
            y: Math.round((controls.keyH - controls.roundD) / 2)
            width: controls.roundD
            height: controls.roundD
            icon: "restart_alt"
            armed: root.context.armed === "reboot"
            u: root.u
            onPressed: {
                root.forceActiveFocus()
                root.context.powerPress("reboot")
            }
        }

        LockPowerKey {
            id: shutKey
            visible: controls.power
            x: restartKey.x + controls.roundD + controls.gap
            y: restartKey.y
            width: controls.roundD
            height: controls.roundD
            icon: "power_settings_new"
            armed: root.context.armed === "poweroff"
            u: root.u
            onPressed: {
                root.forceActiveFocus()
                root.context.powerPress("poweroff")
            }
        }
    }

    // The line under the keys: what a second press will do, which key you are over, or
    // how Ctrl works.
    Text {
        x: controls.x
        y: controls.y + controls.height + root.shadowSmall + root.px(12)
        width: controls.width
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: {
            const a = root.context.armed
            if (a !== "") {
                const what = a === "reboot" ? "RESTART" : "SHUT DOWN"
                return "PRESS AGAIN TO " + what + (PowerBusyService.busy ? " \u2014 " + PowerBusyService.note.toUpperCase() : "")
            }
            if (restartKey.hovered)
                return "RESTART"
            if (shutKey.hovered)
                return "SHUT DOWN"
            return root.context.ctrlHeld ? "ENTER OR CLICK TO SLEEP" : "HOLD CTRL FOR SLEEP"
        }
        color: root.context.armed !== "" ? root.accent : LockPalette.calMuted
        font.family: Theme.fontFamily
        font.pixelSize: root.px(13)
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
        font.letterSpacing: root.px(1)
    }
}
