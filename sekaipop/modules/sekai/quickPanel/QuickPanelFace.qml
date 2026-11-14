import QtQuick
import Quickshell
import QtQuick.Effects
import "../../common/functions/QuickTiles.js" as QT
import "../../common/functions/ImageMath.js" as IM
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.launcher
import qs.modules.sekai.phone

// The Quick Panel's screen: everything that sits inside the phone, drawn
// natively from the Figma frame "Quick Panel Placeholder 2D" (654x1214,
// coordinates are that frame's). PhoneBody.qml supplies the bezel, notch
// and the 2.5D pose; this is the part you tap.
//
// Pure UI (no Quickshell imports): QuickPanel.qml feeds it data through
// plain properties (from QuickSource.qml) and turns its signals into
// actions.
//
// The banner and avatar: click one to pick a picture for it (right-click to
// reset). With no image set they
// show the "empty" look from the Figma template (grey with an account
// icon). Point bannerSource / avatarSource at any image and it's cropped
// to fit.
//
// The list under the "Notifications" tag shows what it's given in
// `notifications` (see NotificationSource.qml): swipe one left or right
// (or tap it) to dismiss it,
// hover the tag and tap it to clear them all. With nothing to show it's
// the grey empty template from Figma.
//
// The heads-up card: when a notification arrives, QuickPanel.qml hands it
// in through `alertEntry` / `alertShown` and it drops in at the top of the
// screen, over the banner and just under the clock row — the phone's own
// "new notification" (there's no separate popup any more). Click it to keep
// the phone up, right-click to dismiss that notification for good.
//
// Right-clicking the Network or Bluetooth tile drops NetworkDialog.qml
// / BluetoothDialog.qml down over the rest of the screen — a Wi-Fi
// network picker and a paired-device list, respectively. Right-clicking
// either volume slider does the same with VolumeMixerDialog.qml, for a
// compact default-device dropdown plus a per-app volume mixer instead.
Item {
    id: face

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
    readonly property bool classicPanel: true

    // Texels per design unit at the size the phone ends up on screen —
    // the same number as PhoneBody.renderScale, fed by QuickPanel.qml.
    // The banner / avatar masks below are layers of their own, and a
    // layer is drawn at its item's design size unless told otherwise, so
    // without this their round edges were made at 1x and then stretched
    // (or squeezed) to whatever size the phone is at, which is what went
    // soft when the scale changed.
    property real renderScale: 1

    width: 654
    height: 1214

    // ===== data =====
    property string clockText: "00:00AM"
    property string dateText: "Sun, 20  Sep"
    // Internet speed, bytes per second (QuickSource.qml samples it), shown
    // top-right as a mirror of the clock + date.
    property real downloadBps: 0
    property real uploadBps: 0
    property string userName: "user"
    property string hostName: "host"
    property url bannerSource: ""
    property url avatarSource: ""
    // Which part of each picture shows (Framing.js; centred = how it always looked).
    property var bannerFraming: null
    property var avatarFraming: null

    // The pointer is on the banner, or on one of the keys / the badge sitting on it (each has
    // its own MouseArea, which takes the hover away from the picture's): one answer for the
    // tint, the keys and the badge, so moving onto a key doesn't flicker them.
    // Not while the phone is only up for a notification (QuickPanel's alertUp without open):
    // it sits low with the banner in reach, and passing over it to get at the card or to
    // leave the phone brought up the Change / Frame keys and the clear badge.
    readonly property bool bannerHovered: !alertOnly && (bannerArea.containsMouse || bannerKeys.hovered || bannerRemoveArea.containsMouse)
    readonly property bool avatarHovered: !alertOnly && (avatarArea.containsMouse || avatarFrameKey.hovered || avatarRemoveArea.containsMouse)

    // "wifi" or "ethernet" — what the first tile is showing
    property string networkKind: "wifi"
    property bool networkOn: false
    property string networkDetail: "OFF"

    property bool bluetoothOn: false
    // A device is connected (on but nothing connected has its own icon).
    property bool bluetoothConnected: false
    property string bluetoothDetail: "OFF"

    property bool microphoneOn: false
    property bool speakerOn: false
    // 0-100, fed from QuickSource.qml (see VolumeSlider.qml below).
    property real microphoneVolume: 0
    property real speakerVolume: 0
    // 0-100, screen brightness for whichever monitor the panel itself is
    // open on — QuickSource.qml resolves that to either brightnessctl
    // (laptop panel) or ddcutil (external monitor) under the hood.
    property real brightness: 100
    // 0-100, screen gamma through hyprsunset (100 = unchanged) — shares a
    // row with Brightness (GammaBrightnessSlider.qml).
    property real gamma: 100
    property bool keepAwakeOn: false
    property string keepAwakeMode: "off"
    property bool notificationsOn: true
    property bool editing: false
    // Night Light / Game Mode, read back from Hyprland by QuickSource.qml.
    property bool nightLightOn: false
    property bool gameModeOn: false
    // The extra buttons, owned by QuickSource.qml. darkModeName is
    // "light" | "dark" | "darker"; powerProfileName "saver" | "balanced" |
    // "performance".
    property bool darkModeOn: false
    property string darkModeName: "light"
    property bool easyEffectsOn: false
    property bool warpOn: false
    property bool warpConnecting: false
    property bool warpInstalled: true
    property bool keyboardOn: false
    property string powerProfileName: "balanced"
    property bool musicListening: false
    property bool antiFlashbangOn: false
    property int antiFlashbangLevel: 0
    // Night Light's card (right-click the tile): how warm it goes (Kelvin)
    // and the Automatic schedule (hours of day). Owned by QuickSource.qml.
    property bool nightLightDialogOpen: false
    property int nightLightTemperature: 4500
    property bool nightLightAuto: false
    property int nightLightAutoFrom: 20
    property int nightLightAutoTo: 6
    // The button grid: [{ id, size: "big" | "small" }], in order — owned by
    // QuickSource.qml, edited through the tile*Requested signals below.
    property var tiles: QT.defaultTiles
    // Most buttons a row may hold, 1-5 — owned by QuickSource.qml, changed
    // from the Columns chips in edit mode.
    property int tileColumns: QT.defaultColumns

    // ===== Wi-Fi / Bluetooth device lists =====
    property bool networkDialogOpen: false
    property bool bluetoothDialogOpen: false
    property bool keepAwakeDialogOpen: false
    property var wifiNetworks: []          // [{ssid, signal, secured, connected}]
    property bool wifiScanning: false
    property bool wifiManualScanning: false
    property string wifiConnectingSsid: ""
    property string wifiConnectError: ""
    property var bluetoothDevices: []      // [{address, name, connected, battery}]
    property bool bluetoothScanning: false
    property bool bluetoothManualScanning: false
    property string bluetoothConnectingAddress: ""
    property string bluetoothConnectError: ""

    signal wifiScanRequested()
    signal wifiAdvancedRequested()
    signal wifiConnectRequested(string ssid, string password)
    signal wifiDisconnectRequested(string ssid)
    signal bluetoothScanRequested()
    signal bluetoothAdvancedRequested()
    signal bluetoothConnectRequested(string address)
    signal bluetoothDisconnectRequested(string address)

    // ===== audio device picker + per-app mixer =====
    property string audioDialogKind: "" // "", "speaker", or "microphone"

    // `audioDialogKind` clears to "" the instant the dialog is asked to
    // close, but the dialog itself (VolumeMixerDialog.qml) then spends
    // 220ms fading out rather than vanishing immediately. Everything
    // that picks the dialog's title/devices/streams below used to
    // branch on `audioDialogKind` directly, which meant the moment you
    // closed, say, the Microphone mixer, every one of those ternaries
    // fell through to its speaker branch (the "else") for that whole
    // 220ms — the dialog visibly swapped to the Speaker mixer's content
    // while it was still fading out. This instead remembers whichever
    // kind was last actually open, and that's what picks the dialog's
    // content, so closing one never flashes the other on its way out.
    // It doesn't need resetting back to "" on close: the moment the
    // dialog opens again, a fresh non-empty kind arrives right away
    // (see the two onRightClicked handlers below) and overwrites it
    // before anything reads it.
    property string _audioDialogShownKind: ""
    // A plain `onAudioDialogKindChanged:` here would collide with the
    // one QuickPanel.qml already sets on this component's own instance
    // (it drives audioMixerActive) — same declarative slot, and the
    // outer one wins, silently dropping this one. Connections listens
    // independently instead, so both run.
    Connections {
        target: face
        function onAudioDialogKindChanged() {
            if (face.audioDialogKind !== "")
                face._audioDialogShownKind = face.audioDialogKind
        }
    }
    readonly property string audioDialogShownKind: audioDialogKind !== "" ? audioDialogKind : _audioDialogShownKind

    property var speakerDevices: []     // [{id, name, active}]
    property var microphoneDevices: []  // [{id, name, active}]
    property var speakerStreams: []     // [{id, name, volume, muted, corked}]
    property var microphoneStreams: []  // [{id, name, volume, muted, corked}]
    property bool audioDevicesScanning: false
    property bool audioDevicesManualScanning: false
    property string audioDeviceSelectingId: ""

    signal audioDeviceScanRequested()
    signal speakerDeviceSelected(string id)
    signal microphoneDeviceSelected(string id)
    signal speakerStreamVolumeChanged(string id, real value)
    signal speakerStreamMuteToggled(string id, bool muted)
    signal microphoneStreamVolumeChanged(string id, real value)
    signal microphoneStreamMuteToggled(string id, bool muted)
    signal speakerStreamDragStarted(string id)
    signal speakerStreamDragEnded(string id)
    signal microphoneStreamDragStarted(string id)
    signal microphoneStreamDragEnded(string id)

    // Tap the phone's Power button (its side button, PhoneBody.powerButton; call
    // togglePowerMenu()) and the rail of eight pills floating
    // beside the phone pops out (see PowerMenu.qml, instantiated by
    // QuickPanel.qml — the rail itself lives outside the phone, so it
    // isn't drawn here). QuickPanel.qml reads this directly to drive
    // that rail's `open` and to close it again when the whole panel
    // goes away; this file only owns the button's own look.
    property bool powerMenuOpen: false

    // Each: { key, app, title, body, time (ms since epoch), urgency }
    property var notifications: []

    // The heads-up card at the top of the screen: the notification that
    // just arrived (same fields as above, plus icon) and whether it's
    // showing right now. The entry stays set after it hides so the card
    // keeps its text while it slides away.
    property var alertEntry: null
    property bool alertShown: false
    // The phone came up only to show that card and hasn't been touched yet.
    property bool alertOnly: false

    // The y (in this file's 654x1214 coordinates) where the bottom of the
    // monitor cuts the phone off — only part of it shows (QuickPanel's
    // `peek`). QuickPanel.qml works it out and passes it in. Because the
    // phone is tilted the cutoff is slanted on the face: lower at the
    // left edge, higher at the right. The notification list runs down to
    // the lower (left) one — whatever hangs past the monitor at the
    // right is simply not drawn — so it fills the screen right to the
    // edge, and scrolls once there are more cards than fit. Left at the
    // full height it behaves as before (the list fills its card).
    property real visibleBottomLeft: 1214
    property real visibleBottomRight: 1214
    // Extra design units below the left cutoff that the open / close
    // bounce briefly pulls into view (QuickPanel's faceRevealLeft). The
    // notification list runs that much further down, hidden under the
    // monitor edge at rest, so the bounce shows cards instead of a cut.
    property real visibleExtra: 0

    // Extra scroll room (design units) under the last notification.
    property real listBottomPad: mt.quickFlat ? 46 : 40

        // "now" for the times on the cards; refreshed while the panel shows.
    property double nowMs: Date.now()

    signal networkToggled()
    signal bluetoothToggled()
    signal microphoneToggled()
    signal speakerToggled()
    // Fired continuously while a slider drags (or on a plain tap-to-set)
    // — QuickPanel.qml forwards these straight to QuickSource's
    // setMicrophoneVolume()/setSpeakerVolume().
    signal microphoneVolumeMoved(real value)
    signal speakerVolumeMoved(real value)
    signal brightnessMoved(real value)
    signal gammaMoved(real value)
    signal keepAwakeToggled()
    signal keepAwakeModeRequested(string mode)
    signal notificationsToggled()
    signal editToggled()
    signal nightLightToggled()
    signal nightLightTemperatureMoved(int kelvin)
    signal nightLightAutoRequested(bool on)
    signal nightLightScheduleRequested(int from, int to)
    signal gameModeToggled()
    signal darkModeToggled()
    signal easyEffectsToggled()
    signal warpToggled()
    signal keyboardToggled()
    signal powerProfileCycled()
    signal musicRecognitionToggled()
    signal antiFlashbangToggled()
    // Screen Snip / Color Picker: a one-shot. The panel closes first.
    signal tileActionRequested(string id)
    // Edit mode (the stylus button): drag a button onto another's spot to
    // move it there, the corner icons remove it / switch big <-> small,
    // and the tray under the grid adds the ones that aren't on the panel.
    signal tileMoveRequested(int from, int to)
    signal tileResizeRequested(int index)
    signal tileRemoveRequested(int index)
    signal tileAddRequested(string id)
    signal tileColumnsRequested(int columns)
    // The Refresh button in the header row (next to Edit / Power):
    // QuickPanel.qml reloads Hyprland's config, then this shell.
    signal refreshRequested()
    // The gear at the left end of that row: QuickPanel.qml turns this phone
    // into the Settings (SettingsStage.qml) where it stands.
    signal settingsRequested()
    signal notificationDismissed(var key)
    // A lone card in the list was clicked: QuickPanel.qml runs the app's own action for
    // it, or dismisses the notification when it has none (what a click always did).
    signal notificationActivated(var key)
    // A whole group (every notification from one source) swiped away.
    signal notificationsDismissed(var keys)
    signal notificationsCleared()
    // The heads-up card was clicked (keep the phone up) / right-clicked
    // (dismiss that notification).
    signal alertActivated()
    signal alertDismissRequested(var key)
    // A left click on the heads-up card: QuickPanel.qml runs the app's own action for that
    // notification, or (when it has none) does what alertActivated() does.
    signal alertClicked(var key)
    // Fired once the "Clear all" cards have finished sliding out and the
    // data behind them is actually gone -- QuickPanel.qml closes on this.
    signal panelCloseRequested()

    // Click the banner or avatar to pick a picture for it; the small
    // badge that appears on hover clears it back to the default.
    // QuickPanel.qml opens the file chooser.
    signal bannerPickRequested()
    signal avatarPickRequested()
    // The Frame keys on the banner and avatar (hover): which part of the picture shows.
    signal bannerFrameRequested()
    signal avatarFrameRequested()
    signal bannerResetRequested()
    signal avatarResetRequested()

    readonly property color placeholderGrey: mt.pSurfaceHover // #f2f2f2

    // ===== the phone wallpaper (LauncherLcd.qml) =====
    // Settings -> General -> Quick Panel -> Phone wallpaper: the same picture the Apps
    // screen shows, as a file path (QuickPanel.qml asks PanelImages.phoneWallpaperFor);
    // "" = none, the plain white screen. Under everything (z). With it there, the two
    // cards let some of it through (`cardAlpha`) and the name under the avatar is white
    // with a dark edge, like the Apps screen's app names. The clock, date and speed sit
    // on the banner, so they keep its ink rule.
    property string wallpaperPath: ""
    // Its framing, for a picture of your own (null: the desktop's wallpaper, centred).
    property var wallpaperFraming: null
    readonly property bool wallOn: face.wallpaperPath !== ""
    // How much of a card's own fill is kept over the wallpaper (1 = none of it shows).
    property real cardAlpha: 0.78

    LauncherLcd {
        id: wallLayer

        z: -10
        x: mt.phoneScreenInset
        y: mt.phoneScreenInset
        width: face.width - 2 * mt.phoneScreenInset
        height: face.height - 2 * mt.phoneScreenInset
        path: face.wallpaperPath
        framing: face.wallpaperFraming
        renderScale: face.renderScale
        // Only decoded while this screen is the one showing.
        active: face.visible
    }


    // ===== the keys a picture shows on hover: Change, Frame =====
    component FaceKey: Item {
        id: fk
        property string icon: ""
        property string text: ""
        property real size: 50
        readonly property bool hovered: fkArea.containsMouse
        signal clicked()
        implicitWidth: (fk.text === "" ? fk.size : fkRow.implicitWidth + 34) + 4
        implicitHeight: fk.size + 4
        // A little see-through at rest, like the remove badge; solid under the pointer.
        opacity: fk.hovered ? 1 : 0.8
        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
        Rectangle {
            x: 4
            y: 4
            width: fk.width - 4
            height: fk.height - 4
            radius: height / 2
            color: mt.pLineShadow
        }
        Rectangle {
            width: fk.width - 4
            height: fk.height - 4
            x: fkArea.pressed ? 4 : 0
            y: fkArea.pressed ? 4 : 0
            radius: height / 2
            color: fkArea.containsMouse ? mt.pSurfaceHover : mt.pSurface
            border.width: 3
            border.color: fkArea.containsMouse ? mt.colBorder : mt.pLine
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: height / 2
                color: "transparent"
                border.width: 3
                border.color: mt.pRingWhite
            }
            Row {
                id: fkRow
                anchors.centerIn: parent
                spacing: 8
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: fk.icon
                    size: fk.text === "" ? 20 : 22
                    color: mt.pInk
                }
                Text {
                    visible: fk.text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: fk.text
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 19
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }
        }
        MouseArea {
            id: fkArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fk.clicked()
        }
    }

    // ===== text colour over the banner =====
    property bool bannerDarkLeft: false
    property bool bannerDarkRight: false
    readonly property bool bannerHasImage: bannerImage.status === Image.Ready
    readonly property color bannerInkLeft: bannerHasImage
        ? (bannerDarkLeft ? "#ffffff" : mt.colBorder) : mt.pInk
    readonly property color bannerInkRight: bannerHasImage
        ? (bannerDarkRight ? "#ffffff" : mt.colBorder) : mt.pInk

    // ===== banner =====
    Item {
        id: banner
        x: 26
        y: 26
        width: 602
        height: 240

        // Empty look
        Rectangle {
            anchors.fill: parent
            color: face.placeholderGrey
            topLeftRadius: 74
            topRightRadius: 74
            bottomLeftRadius: 50
            bottomRightRadius: 50
            visible: bannerImage.status !== Image.Ready
        }

        // The picture, framed (PanelImages.framingFor: which part shows) and cropped
        // into the same shape. Decoded at 2x the size it is drawn: this lives for the
        // whole session (QuickPanel is made once in shell.qml), so it never holds the
        // photo at its own size.
        FramedImage {
            id: bannerImage
            anchors.fill: parent
            source: face.bannerSource
            framing: face.bannerFraming
            decodeScale: 2
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                       Math.ceil(height * face.renderScale * 2))
        }

        // Measures the banner's brightness under the clock/date and under the
        // speed readout. Invisible (opacity 0, never shown), 60x24 = the
        // banner at 1/10 size, so a paint costs next to nothing and only
        // happens when the picture changes.
        Canvas {
            id: bannerSampler
            width: 60
            height: 24
            opacity: 0
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate

            readonly property url src: bannerImage.status === Image.Ready ? bannerImage.source : ""
            // Measured again when the framing moves what is under the text.
            readonly property var framing: face.bannerFraming

            onSrcChanged: {
                if (src.toString() !== "")
                    loadImage(src)
            }
            onFramingChanged: requestPaint()
            onImageLoaded: requestPaint()

            // Average brightness (0 black .. 1 white, in linear light) of a
            // rectangle of the thumbnail.
            function brightness(ctx, x, y, w, h) {
                const d = ctx.getImageData(x, y, w, h).data
                let sum = 0
                let n = 0
                for (let i = 0; i < d.length; i += 4) {
                    if (d[i + 3] === 0)
                        continue
                    const r = Math.pow(d[i] / 255, 2.2)
                    const g = Math.pow(d[i + 1] / 255, 2.2)
                    const b = Math.pow(d[i + 2] / 255, 2.2)
                    sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    n++
                }
                return n > 0 ? sum / n : 1
            }

            onPaint: {
                if (src.toString() === "" || !isImageLoaded(src))
                    return
                if (!(bannerImage.aspect > 0))
                    return

                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                // Draw it the way the banner does: framed (zoomed and panned) to
                // cover the thumbnail, the overflow cut off.
                const f = face.bannerFraming || {}
                const r = IM.drawRect(width, height, bannerImage.aspect * 1000, 1000, "crop",
                                      f.zoom === undefined ? 1 : f.zoom, f.panX || 0, f.panY || 0)
                ctx.drawImage(src, r.x, r.y, r.w, r.h)

                // Under the clock + date: banner x 41..191, y 10..60.
                // Under the speed readout: banner x 411..561, y 12..58.
                // Below ~0.30 the picture is dark enough that white text wins.
                face.bannerDarkLeft = brightness(ctx, 4, 1, 15, 5) < 0.30
                face.bannerDarkRight = brightness(ctx, 41, 1, 15, 5) < 0.30
            }
        }

        Item {
            id: bannerMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                       Math.ceil(height * face.renderScale * 2))

            Rectangle {
                anchors.fill: parent
                color: "black"
                topLeftRadius: 74
                topRightRadius: 74
                bottomLeftRadius: 50
                bottomRightRadius: 50
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: bannerImage
            maskEnabled: true
            maskSource: bannerMask
            visible: bannerImage.status === Image.Ready
        }

        // Hover: a light tint and a pencil, so it's clear it can be changed
        Rectangle {
            anchors.fill: parent
            color: mt.pLine
            opacity: face.bannerHovered ? 0.14 : 0
            topLeftRadius: 74
            topRightRadius: 74
            bottomLeftRadius: 50
            bottomRightRadius: 50

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        MaterialIcon {
            name: "stylus"
            size: 32
            anchors.centerIn: parent
            // Only while there is no picture: with one, the Change / Frame keys say it.
            opacity: face.bannerHovered && bannerImage.status !== Image.Ready ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        // Declared last in the banner, but the clock, avatar and buttons
        // that overlap it are declared after the banner itself, so they
        // still get their own clicks.
        MouseArea {
            id: bannerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                face.bannerPickRequested()
                face.panelCloseRequested()
            }
        }

        // On hover, with a picture: Change it, or Frame it (which part shows). Declared
        // after bannerArea so they take their own clicks; they keep the hover between them.
        Row {
            id: bannerKeys
            readonly property bool hovered: changeKey.hovered || frameKey.hovered
            visible: bannerImage.status === Image.Ready && face.bannerHovered
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 20
            spacing: 10
            FaceKey {
                id: changeKey
                icon: "image"
                text: "Change"
                onClicked: {
                    face.bannerPickRequested()
                    face.panelCloseRequested()
                }
            }
            FaceKey {
                id: frameKey
                icon: "crop"
                text: "Frame"
                onClicked: {
                    face.panelCloseRequested()
                    face.bannerFrameRequested()
                }
            }
        }

        // A small "clear" badge, top-right, so removing a set banner
        // doesn't need a right-click to discover -- only shown once
        // there's actually something to clear, and only on hover, same
        // as the pencil hint above. Declared after bannerArea so it
        // sits on top and catches its own clicks rather than triggering
        // a re-pick underneath it.
        Rectangle {
            id: bannerRemove
            // Same fix as ever: include bannerRemoveArea's own hover so the badge doesn't fight
            // itself for visibility once the cursor is on it.
            // Two clicks to remove (the picture's stored copy is deleted, there is no
            // getting it back): the first arms the badge, which widens into "Remove?",
            // the second removes. Leaving it, or 3 s, disarms it.
            property bool armed: false
            visible: bannerImage.status === Image.Ready
                && face.bannerHovered
            onVisibleChanged: if (!visible) armed = false
            // Right-aligned, so it grows to the left when armed; below the speed readout.
            x: banner.width - width - 24
            y: 84
            width: armed ? bannerRemoveLabel.implicitWidth + 32 + 6 : 32
            height: 32
            radius: height / 2
            color: armed ? mt.accentCyan : mt.pLine
            opacity: bannerRemoveArea.containsMouse || armed ? 1 : 0.8
            antialiasing: true

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 4
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: bannerRemove.armed ? "delete" : "close"
                    size: 18
                    fill: 1
                    color: bannerRemove.armed ? mt.colBorder : "white"
                }
                Text {
                    id: bannerRemoveLabel
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bannerRemove.armed
                    text: "Remove?"
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 18 - 3
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            Timer {
                interval: 3000
                running: bannerRemove.armed
                onTriggered: bannerRemove.armed = false
            }

            MouseArea {
                id: bannerRemoveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (bannerRemove.armed) {
                        bannerRemove.armed = false
                        face.bannerResetRequested()
                    } else {
                        bannerRemove.armed = true
                    }
                }
            }
        }
    }

    // ===== clock + date =====
    Column {
        x: 67
        y: 36
        spacing: -7

        Text {
            text: face.clockText
            color: face.bannerInkLeft
            font.family: mt.fontFamily
            font.pixelSize: 24
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Text {
            text: face.dateText
            color: face.bannerInkLeft
            font.family: mt.fontFamily
            font.pixelSize: 20
        }
    }

    // ===== internet speed =====
    function formatRate(bps) {
        if (bps >= 1048576)
            return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024)
            return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    Column {
        id: speedBlock
        x: 654 - 67 - width
        y: 38
        width: 150
        spacing: -2

        Item {
            width: speedBlock.width
            height: downText.implicitHeight

            MaterialIcon {
                id: downIcon
                name: "arrow_downward"
                size: 20
                weight: 600
                color: face.bannerInkRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: downText
                anchors.right: downIcon.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: face.formatRate(face.downloadBps)
                color: face.bannerInkRight
                font.family: mt.fontFamily
                font.pixelSize: 20
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        Item {
            width: speedBlock.width
            height: upText.implicitHeight

            MaterialIcon {
                id: upIcon
                name: "arrow_upward"
                size: 20
                weight: 600
                color: face.bannerInkRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: upText
                anchors.right: upIcon.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: face.formatRate(face.uploadBps)
                color: face.bannerInkRight
                font.family: mt.fontFamily
                font.pixelSize: 20
            }
        }
    }

    // ===== avatar + user@host =====
    Item {
        id: avatar
        x: 67
        y: 208
        width: 120
        height: 120

        // The picture (and its mask / placeholder / hover tint) stops this
        // far inside the outer edge, so its soft anti-aliased rim sits UNDER
        // the 3px ring instead of poking out past it. Bigger = tighter.
        readonly property real imgInset: 2

        Rectangle {
            anchors.fill: parent
            anchors.margins: avatar.imgInset
            radius: width / 2
            color: face.placeholderGrey
            visible: avatarImage.status !== Image.Ready
            antialiasing: true
        }

        MaterialIcon {
            name: "account_circle"
            size: 24
            anchors.centerIn: parent
            visible: avatarImage.status !== Image.Ready && !face.avatarHovered
        }

        // Framed like the banner (PanelImages.framingFor("avatar")), decoded at 2x.
        FramedImage {
            id: avatarImage
            anchors.fill: parent
            anchors.margins: avatar.imgInset
            source: face.avatarSource
            framing: face.avatarFraming
            decodeScale: 2
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                       Math.ceil(height * face.renderScale * 2))
        }

        Item {
            id: avatarMask
            anchors.fill: parent
            anchors.margins: avatar.imgInset
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(width * face.renderScale * 2),
                                       Math.ceil(height * face.renderScale * 2))

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "black"
                antialiasing: true
            }
        }

        MultiEffect {
            anchors.fill: parent
            anchors.margins: avatar.imgInset
            source: avatarImage
            maskEnabled: true
            maskSource: avatarMask
            visible: avatarImage.status === Image.Ready
        }

        // Hover: a light tint and a pencil, like the banner
        Rectangle {
            anchors.fill: parent
            anchors.margins: avatar.imgInset
            radius: width / 2
            color: mt.pLine
            opacity: face.avatarHovered ? 0.14 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
            antialiasing: true
        }

        MaterialIcon {
            name: "stylus"
            size: 28
            anchors.centerIn: parent
            opacity: face.avatarHovered ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        // The white ring around it
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: mt.pRingWhite
            antialiasing: true
        }

        MouseArea {
            id: avatarArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                face.avatarPickRequested()
                face.panelCloseRequested()
            }
        }

        // Same clear badge as the banner's, sized down and tucked into
        // the bottom-right of the circle (a common "remove this avatar"
        // spot) so it doesn't cover the white ring's top edge.
        // On hover, with a picture: Frame it (which part shows), bottom-left (the remove
        // badge holds the bottom-right). A click on the avatar itself still changes it.
        FaceKey {
            id: avatarFrameKey
            visible: avatarImage.status === Image.Ready && face.avatarHovered
            x: -6
            y: avatar.height - height + 2
            size: 40
            icon: "crop"
            onClicked: {
                face.panelCloseRequested()
                face.avatarFrameRequested()
            }
        }

        Rectangle {
            id: avatarRemove
            // Same fix as ever: include avatarRemoveArea's own hover so the badge doesn't fight
            // itself for visibility once the cursor is on it.
            // Two clicks to remove (the picture's stored copy is deleted, there is no
            // getting it back): the first arms the badge, which widens into "Remove?",
            // the second removes. Leaving it, or 3 s, disarms it.
            property bool armed: false
            visible: avatarImage.status === Image.Ready
                && face.avatarHovered
            onVisibleChanged: if (!visible) armed = false
            // Bottom-right of the circle, growing to the left when armed.
            x: avatar.width - width - 2
            y: avatar.height - height - 2
            width: armed ? avatarRemoveLabel.implicitWidth + 28 + 6 : 28
            height: 28
            radius: height / 2
            color: armed ? mt.accentCyan : mt.pLine
            opacity: avatarRemoveArea.containsMouse || armed ? 1 : 0.8
            antialiasing: true

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 4
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: avatarRemove.armed ? "delete" : "close"
                    size: 16
                    fill: 1
                    color: avatarRemove.armed ? mt.colBorder : "white"
                }
                Text {
                    id: avatarRemoveLabel
                    anchors.verticalCenter: parent.verticalCenter
                    visible: avatarRemove.armed
                    text: "Remove?"
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 16 - 3
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            Timer {
                interval: 3000
                running: avatarRemove.armed
                onTriggered: avatarRemove.armed = false
            }

            MouseArea {
                id: avatarRemoveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (avatarRemove.armed) {
                        avatarRemove.armed = false
                        face.avatarResetRequested()
                    } else {
                        avatarRemove.armed = true
                    }
                }
            }
        }
    }

    Text {
        x: 67
        y: 331
        // (The header buttons start at x 329 beside it (there is no Power button
        // in the header any more: it is the phone's own side button), so this stops
        // at 321; a long name is cut with "...".)
        width: 254
        elide: Text.ElideRight
        text: face.userName + "@" + face.hostName
        color: face.wallOn ? "#ffffff" : mt.pInk
        style: face.wallOn ? Text.Outline : Text.Normal
        styleColor: Qt.rgba(0.10, 0.10, 0.22, 0.85)
        font.family: mt.fontFamily
        font.pixelSize: 20
    }

    // ===== Settings / Refresh / Edit =====
    // The header row's first button and the gap between buttons: Settings, Refresh,
    // Edit. (The Apps button that used to be first is gone: the Apps screen is
    // reached with Super + A, by typing, or from the dock's Search key. The Power
    // button that used to be last is the phone's own side button now, see
    // PhoneBody.powerButton; the row keeps its right end where it was, so the
    // three buttons moved over by one pitch.)
    readonly property real headerX: 329
    readonly property real headerPitch: 89

    // The Power button (the phone's side button, PhoneBody.powerButton): one tap
    // opens the rail of pills beside the phone, another tap (or the scrim) closes
    // it. Opening it puts any dialog away.
    function togglePowerMenu() {
        if (face.powerMenuOpen) {
            face.powerMenuOpen = false
        } else {
            face.powerMenuOpen = true
            face.networkDialogOpen = false
            face.bluetoothDialogOpen = false
            face.nightLightDialogOpen = false
            face.audioDialogKind = ""
        }
    }

    QuickToggle {
        flatShadow: mt.quickFlat
        kind: "square"
        x: face.headerX
        y: 276
        hoverLights: true
        icon: "settings"
        onClicked: face.settingsRequested()
    }

    QuickToggle {
        flatShadow: mt.quickFlat
        kind: "square"
        x: face.headerX + face.headerPitch
        y: 276
        hoverLights: true
        icon: "refresh"
        onClicked: face.refreshRequested()
    }

    QuickToggle {
        flatShadow: mt.quickFlat
        kind: "square"
        x: face.headerX + face.headerPitch * 2
        y: 276
        hoverLights: true
        on: face.editing
        icon: "stylus"
        onClicked: face.editToggled()
    }

    // ===== toggles =====
    // ===== button grid =====
    readonly property var tileLayout: QT.pack(face.tiles, face.tileColumns, mt.quickFlat)
    property real tileExtra: tileLayout.height - QT.baseGridHeight
    Behavior on tileExtra {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    // While a button is being dragged: the index of the slot it would land
    // in if let go now (-1 when nothing is being dragged).
    property int dropIndex: -1

    // The catalog buttons that aren't on the panel right now, for the add
    // tray in edit mode; and whether one more small button would still fit.
    readonly property var unplacedTiles: QT.catalog.filter(id => !face.tiles.some(t => t.id === id))
    readonly property bool canAdd: QT.fits(face.tiles.concat([{ id: "_", size: "small" }]), face.tileColumns)

    // Would the resize badge do anything for the button at `index`? (It
    // cycles small -> big -> long -> small, skipping sizes that wouldn't
    // fit; shrinking always does.) Drives the dimmed look of the badge.
    function canResize(index) {
        if (index < 0 || index >= face.tiles.length)
            return false
        return QT.nextSize(face.tiles, index, face.tileColumns) !== face.tiles[index].size
    }

    // Does the badge grow the button (open-out icon) or shrink it?
    function resizeGrows(index) {
        if (index < 0 || index >= face.tiles.length)
            return true
        const next = QT.nextSize(face.tiles, index, face.tileColumns)
        return QT.unitsOf(next) > QT.unitsOf(face.tiles[index].size)
    }

    // Would `columns` buttons per row still fit under the row limit with the
    // buttons that are on the panel now? (More columns always do.)
    function canColumns(columns) {
        return QT.fits(face.tiles, columns)
    }

    // The slot whose centre is nearest the pointer (face coordinates).
    function tileSlotNear(px, py) {
        const slots = face.tileLayout.slots
        let best = -1
        let bestD = 1e12
        for (let i = 0; i < slots.length; i++) {
            const cx = 67 + slots[i].x + slots[i].w / 2
            const cy = 373 + slots[i].y + slots[i].rowH / 2
            const d = (px - cx) * (px - cx) + (py - cy) * (py - cy)
            if (d < bestD) {
                bestD = d
                best = i
            }
        }
        return best
    }

    // What each button looks like and does, by id. The functions read the
    // panel's own properties, so a button re-reads them when they change.
    function tileName(id) {
        switch (id) {
        case "network": return face.networkKind === "ethernet" ? "Ethernet" : "Wi-Fi"
        case "bluetooth": return "Bluetooth"
        case "keepAwake": return "Keep Awake"
        case "microphone": return "Microphone"
        case "speaker": return "Speaker"
        case "notifications": return "Alerts"
        case "nightLight": return "Night Light"
        case "gameMode": return "Game Mode"
        case "darkMode": return "Dark Mode"
        case "easyEffects": return "Easy Effects"
        case "warp": return "Cloudflare WARP"
        case "screenSnip": return "Screen Snip"
        case "colorPicker": return "Color Picker"
        case "keyboard": return "On-Screen Keyboard"
        case "powerProfile": return "Power Profile"
        case "musicRecognition": return "Music Recognition"
        case "antiFlashbang": return "Anti-Flashbang"
        }
        return ""
    }

    function tileOn(id) {
        switch (id) {
        case "network": return face.networkOn
        case "bluetooth": return face.bluetoothOn
        case "keepAwake": return face.keepAwakeOn
        case "microphone": return face.microphoneOn
        case "speaker": return face.speakerOn
        case "notifications": return face.notificationsOn
        case "nightLight": return face.nightLightOn
        case "gameMode": return face.gameModeOn
        case "darkMode": return face.darkModeOn
        case "easyEffects": return face.easyEffectsOn
        case "warp": return face.warpOn || face.warpConnecting
        case "keyboard": return face.keyboardOn
        case "powerProfile": return face.powerProfileName === "performance"
        case "musicRecognition": return face.musicListening
        case "antiFlashbang": return face.antiFlashbangOn
        }
        return false
    }

    function tileSubtitle(id) {
        switch (id) {
        case "network": return face.networkDetail
        case "bluetooth": return face.bluetoothDetail
        case "keepAwake": return face.keepAwakeOn ? "ON" : "OFF"
        case "microphone": return face.microphoneOn ? "ON" : "Muted"
        case "speaker": return face.speakerOn ? "ON" : "Muted"
        case "notifications": return face.notificationsOn ? "ON" : "Muted"
        case "nightLight": return face.nightLightOn ? face.nightLightTemperature + "K"
                                                    : (face.nightLightAuto ? "AUTO" : "OFF")
        case "gameMode": return face.gameModeOn ? "ON" : "OFF"
        case "darkMode": return face.darkModeName === "light" ? "Light" : (face.darkModeName === "darker" ? "Darker" : "Dark")
        case "easyEffects": return face.easyEffectsOn ? "ON" : "OFF"
        case "warp": return !face.warpInstalled ? "Not installed"
                              : (face.warpConnecting ? "Connecting…" : (face.warpOn ? "ON" : "OFF"))
        case "screenSnip": return "Tap"
        case "colorPicker": return "Tap"
        case "keyboard": return face.keyboardOn ? "ON" : "OFF"
        case "powerProfile": return face.powerProfileName === "saver" ? "Saver" : (face.powerProfileName === "performance" ? "Performance" : "Balanced")
        case "musicRecognition": return face.musicListening ? "Listening…" : "Tap"
        case "antiFlashbang": return face.antiFlashbangLevel === 1 ? "Weak" : (face.antiFlashbangLevel === 2 ? "Strong" : "OFF")
        }
        return ""
    }

    function tileIcon(id) {
        switch (id) {
        case "network":
            return face.networkKind === "ethernet" ? "settings_ethernet"
                                                   : (face.networkOn ? "wifi" : "wifi_off")
        // off / on with nothing connected / a device connected
        case "bluetooth": return !face.bluetoothOn ? "bluetooth_disabled"
                                                   : (face.bluetoothConnected ? "bluetooth_connected" : "bluetooth")
        case "keepAwake": return "emoji_food_beverage"
        case "microphone": return face.microphoneOn ? "mic" : "mic_off"
        case "speaker": return face.speakerOn ? "volume_up" : "volume_off"
        case "notifications": return face.notificationsOn ? "notifications_active" : "notifications_off"
        case "nightLight": return "bedtime"
        case "gameMode": return "gamepad"
        case "darkMode": return face.darkModeName === "light" ? "light_mode" : (face.darkModeName === "darker" ? "bedtime" : "dark_mode")
        case "easyEffects": return "graphic_eq"
        case "warp": return "vpn_lock"
        case "screenSnip": return "screenshot_region"
        case "colorPicker": return "colorize"
        case "keyboard": return "keyboard"
        case "powerProfile": return face.powerProfileName === "saver" ? "energy_savings_leaf" : (face.powerProfileName === "performance" ? "speed" : "balance")
        case "musicRecognition": return "music_cast"
        case "antiFlashbang": return "flash_off"
        }
        return ""
    }

    // Solid glyph while ON, for the ones whose icon has no state of its own.
    // Keep Awake is not in the list on purpose: its icon stays outline.
    function tileFilled(id) {
        return (id === "nightLight" || id === "gameMode"
                || id === "easyEffects" || id === "warp" || id === "keyboard"
                || id === "musicRecognition" || id === "antiFlashbang") && face.tileOn(id)
    }

    function tileClicked(id) {
        switch (id) {
        case "network": face.networkToggled(); break
        case "bluetooth": face.bluetoothToggled(); break
        case "keepAwake": face.keepAwakeToggled(); break
        case "microphone": face.microphoneToggled(); break
        case "speaker": face.speakerToggled(); break
        case "notifications": face.notificationsToggled(); break
        case "nightLight": face.nightLightToggled(); break
        case "gameMode": face.gameModeToggled(); break
        case "darkMode": face.darkModeToggled(); break
        case "easyEffects": face.easyEffectsToggled(); break
        case "warp": face.warpToggled(); break
        case "keyboard": face.keyboardToggled(); break
        case "powerProfile": face.powerProfileCycled(); break
        case "musicRecognition": face.musicRecognitionToggled(); break
        case "antiFlashbang": face.antiFlashbangToggled(); break
        case "screenSnip":
        case "colorPicker":
            face.panelCloseRequested()
            face.tileActionRequested(id)
            break
        }
    }

    // Right-click: Wi-Fi, Bluetooth, Microphone and Speaker have a list to
    // show, Night Light has its intensity / Automatic card. Ethernet has no
    // network list to pick from, so it does nothing. Only one of these is
    // ever open: opening one closes the rest.
    function closeDialogs() {
        face.keepAwakeDialogOpen = false
        face.networkDialogOpen = false
        face.bluetoothDialogOpen = false
        face.nightLightDialogOpen = false
        face.powerMenuOpen = false
        face.audioDialogKind = ""
    }

    function tileRightClicked(id) {
        if (id === "network" && face.networkKind !== "ethernet") {
            face.closeDialogs()
            face.networkDialogOpen = true
        } else if (id === "bluetooth") {
            face.closeDialogs()
            face.bluetoothDialogOpen = true
        } else if (id === "nightLight") {
            face.closeDialogs()
            face.nightLightDialogOpen = true
        } else if (id === "microphone" || id === "speaker") {
            face.closeDialogs()
            face.audioDialogKind = id
        } else if (id === "keepAwake") {
            face.closeDialogs()
            face.keepAwakeDialogOpen = true
        }
    }

    Rectangle {
        x: 40
        y: 362
        width: 575
        height: 275 + face.tileExtra
        radius: 40
        color: face.wallOn ? Qt.alpha(face.placeholderGrey, face.cardAlpha) : face.placeholderGrey
        antialiasing: true
    }

    // One slot per catalog button, always present: a button that isn't on
    // the panel is just hidden, and one that moves keeps its own item and
    // slides to its new slot (so reordering animates instead of swapping
    // text between fixed boxes).
    Repeater {
        model: QT.catalog

        delegate: Item {
            id: tile

            required property string modelData

            // Where this button is in the list, -1 if it isn't on the panel.
            readonly property int pos: {
                const t = face.tiles
                for (let i = 0; i < t.length; i++) {
                    if (t[i].id === tile.modelData)
                        return i
                }
                return -1
            }
            readonly property bool placed: pos >= 0
            // Its slot in the layout. For a moment after the list changes `pos` can point past the
            // layout that has not been recomputed yet; the Bindings below then wait.
            readonly property var slot: pos >= 0 ? face.tileLayout.slots[pos] : undefined

            // Kept as they were while the button is off the panel (the
            // Bindings below only follow the list while it's on), so a
            // removed button fades out where it stood instead of jumping.
            property string sizeName: "small"   // "small" | "big" | "long"
            readonly property bool big: sizeName !== "small"
            // How wide the button is drawn: its size's own width, or wider
            // when its row stretches to fill the panel (QT.pack).
            property real slotW: 74
            property real slotX: 67
            property real slotY: 373

            Binding {
                target: tile
                property: "sizeName"
                value: tile.placed ? face.tiles[tile.pos].size : "small"
                when: tile.placed
            }
            Binding {
                target: tile
                property: "slotW"
                value: tile.slot ? tile.slot.w : 74
                when: tile.placed && tile.slot !== undefined
            }
            Binding {
                target: tile
                property: "slotX"
                value: 67 + (tile.slot ? tile.slot.x : 0)
                when: tile.placed && tile.slot !== undefined
            }
            Binding {
                target: tile
                property: "slotY"
                // The row's top, plus how far down in the row this button
                // sits (centred against a taller neighbour, or level with it in 2D — see QT.pack).
                value: 373 + (tile.slot ? tile.slot.y + tile.slot.oy : 0)
                when: tile.placed && tile.slot !== undefined
            }

            property bool dragging: false
            property real dragX: 0
            property real dragY: 0

            x: dragging ? dragX : slotX
            y: dragging ? dragY : slotY
            z: dragging ? 20 : 0
            // Microphone / Speaker at the big and long sizes are the volume
            // slider; at the small size (and every other button) it's a
            // QuickToggle.
            readonly property bool sliderMode: QT.isSlider(modelData) && big
            width: sliderMode ? slider.implicitWidth + 5 : toggle.implicitWidth
            height: sliderMode ? slider.implicitHeight : toggle.implicitHeight

            opacity: placed ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
            Behavior on slotW {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on x {
                enabled: !tile.dragging
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                enabled: !tile.dragging
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            VolumeSlider {
                id: slider
                flatShadow: mt.quickFlat
                visible: tile.sliderMode
                sliderWidth: tile.slotW
                // Edit mode takes over the mouse (see editArea below), so
                // dragging a button doesn't also set the volume.
                enabled: !face.editing
                label: face.tileName(tile.modelData)
                icon: face.tileIcon(tile.modelData)
                muted: !face.tileOn(tile.modelData)
                value: tile.modelData === "microphone" ? face.microphoneVolume : face.speakerVolume
                onIconClicked: face.tileClicked(tile.modelData)
                onMoved: value => {
                    if (tile.modelData === "microphone")
                        face.microphoneVolumeMoved(value)
                    else
                        face.speakerVolumeMoved(value)
                }
                onRightClicked: face.tileRightClicked(tile.modelData)
            }

            QuickToggle {
                flatShadow: mt.quickFlat
                id: toggle
                visible: !tile.sliderMode
                // Wide (icon + name + status, e.g. the Wi-Fi network or the
                // connected Bluetooth device) for the 2- and 3-column sizes,
                // and also for a small button whose row got stretched in
                // 2-column mode: it would otherwise be a wide, empty
                // icon-only pill with the name and active device hidden.
                kind: (tile.big || (face.tileColumns <= 2 && tile.slotW >= 140)) ? "wide" : "round"
                wideWidth: tile.slotW
                roundWidth: tile.slotW
                // Same reason as the slider above: a click while arranging
                // doesn't flip Wi-Fi off.
                enabled: !face.editing
                on: face.tileOn(tile.modelData)
                label: face.tileName(tile.modelData)
                subtitle: face.tileSubtitle(tile.modelData)
                icon: face.tileIcon(tile.modelData)
                iconFilled: face.tileFilled(tile.modelData)
                onClicked: face.tileClicked(tile.modelData)
                onRightClicked: face.tileRightClicked(tile.modelData)
            }

            // Edit mode: press and drag to move. A press that never moves
            // does nothing (removing / resizing are the badges below, so
            // a stray tap can't delete a button). Letting go over another
            // slot asks for the move; the button then slides there.
            MouseArea {
                id: editArea
                anchors.fill: parent
                visible: face.editing && tile.placed
                enabled: visible
                hoverEnabled: true
                cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property real grabX: 0
                property real grabY: 0

                function endDrag() {
                    if (!tile.dragging)
                        return
                    tile.dragging = false
                    const to = face.dropIndex
                    face.dropIndex = -1
                    if (to >= 0 && to !== tile.pos)
                        face.tileMoveRequested(tile.pos, to)
                }

                onPressed: mouse => {
                    grabX = mouse.x
                    grabY = mouse.y
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return
                    if (!tile.dragging && Math.abs(mouse.x - grabX) + Math.abs(mouse.y - grabY) < 8)
                        return
                    // Where the pointer is in the face's own coordinates;
                    // the button is placed so the spot it was grabbed at
                    // stays under the pointer.
                    const p = mapToItem(face, mouse.x, mouse.y)
                    tile.dragging = true
                    tile.dragX = p.x - grabX
                    tile.dragY = p.y - grabY
                    face.dropIndex = face.tileSlotNear(p.x, p.y)
                }
                onReleased: endDrag()
                onCanceled: endDrag()
            }

            // Remove (top-left) and resize (top-right) badges, the
            // same little navy discs the banner's clear badge uses.
            Rectangle {
                id: removeBadge
                visible: face.editing && tile.placed && !tile.dragging
                x: -7
                y: -7
                width: 24
                height: 24
                radius: width / 2
                color: mt.pLine
                antialiasing: true

                MaterialIcon {
                    name: "remove"
                    size: 16
                    fill: 1
                    color: "white"
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: face.tileRemoveRequested(tile.pos)
                }
            }

            Rectangle {
                id: resizeBadge
                visible: face.editing && tile.placed && !tile.dragging
                x: tile.slotW - width + 7
                y: -7
                width: 24
                height: 24
                radius: width / 2
                color: mt.pLine
                // Dimmed when no other size would fit (the panel is full).
                opacity: face.canResize(tile.pos) ? 1 : 0.35
                antialiasing: true

                MaterialIcon {
                    name: face.resizeGrows(tile.pos) ? "open_in_full" : "close_fullscreen"
                    size: 14
                    fill: 1
                    color: "white"
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    enabled: face.canResize(tile.pos)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: face.tileResizeRequested(tile.pos)
                }
            }
        }
    }

    // Where a dragged button would land: an outline around that slot.
    Rectangle {
        readonly property bool shown: face.editing && face.dropIndex >= 0 && face.dropIndex < face.tiles.length
        readonly property var dropSlot: shown ? face.tileLayout.slots[face.dropIndex] : null
        visible: shown
        x: 67 + (dropSlot ? dropSlot.x : 0) - 5
        y: 373 + (dropSlot ? dropSlot.y : 0) - 4
        width: (dropSlot ? dropSlot.w : 0) + 10
        height: (dropSlot ? dropSlot.rowH : 75) + 8
        radius: 44
        color: "transparent"
        border.width: 3
        border.color: mt.accentCyan
        antialiasing: true
    }

    // Gamma + Brightness as ONE slider under the button grid: a single
    // track whose short first stretch is gamma and the rest brightness
    // (GammaBrightnessSlider.qml). Neither is one of the arrangeable
    // buttons, so it stays put and just follows the grid's height. Plain
    // label headers (no cap/button) — there's no mute or right-click
    // dialog for either.
    GammaBrightnessSlider {
        x: 67
        y: 570 + face.tileExtra
        sliderWidth: 514
        gamma: face.gamma
        brightness: face.brightness
        onGammaMoved: value => face.gammaMoved(value)
        onBrightnessMoved: value => face.brightnessMoved(value)
    }

    // ===== notifications =====
    Timer {
        interval: 20000
        repeat: true
        running: face.visible
        onTriggered: face.nowMs = Date.now()
    }

    onVisibleChanged: {
        if (visible)
            nowMs = Date.now()
    }

    // The list shows this ListModel, kept in step with `notifications`
    // by syncNotifications() below, rather than showing the array itself.
    // A plain array replaces the whole list every time anything changes,
    // so the ListView can't tell "this one card left" from "everything
    // changed" and just jumps; with a real model it knows which row went
    // where, and can slide the cards underneath up into the gap (the
    // `remove` / `displaced` transitions on the list).
    ListModel {
        id: listModel
    }

    // ===== grouping =====
    function groupIdOf(n) {
        return n.app !== "" ? n.app : "#" + n.key
    }

    // Which groups are opened (gid -> true). Kept here, not in the list's
    // delegates, so a group stays open while notifications come and go.
    property var expandedGroups: ({})

    function toggleGroup(gid) {
        const m = Object.assign({}, expandedGroups)
        if (m[gid])
            delete m[gid]
        else
            m[gid] = true
        expandedGroups = m
    }

    // Every notification of a group, newest first.
    function groupItems(gid) {
        return notifications.filter(n => groupIdOf(n) === gid)
    }

    function groupKeys(gid) {
        return groupItems(gid).map(n => n.key)
    }

    // -> [{ gid, count, urgency, n }] newest group first; `n` is the group's
    // newest notification (what the collapsed card shows) and `urgency` the
    // most urgent one inside it.
    function groupsOf(list) {
        const order = []
        const map = Object.create(null)
        for (let i = 0; i < list.length; i++) {
            const gid = groupIdOf(list[i])
            if (!(gid in map)) {
                map[gid] = { gid: gid, count: 0, urgency: 0, n: list[i] }
                order.push(gid)
            }
            map[gid].count++
            map[gid].urgency = Math.max(map[gid].urgency, list[i].urgency)
        }
        return order.map(gid => map[gid])
    }

    // Only the fields the cards use. (Not the whole entry: its extra
    // `index` field would clash with the delegate's own `index`.)
    function cardData(g) {
        return {
            gid: g.gid,
            key: g.n.key,
            app: g.n.app,
            title: g.n.title,
            body: g.n.body,
            time: g.n.time,
            urgency: g.urgency,
            icon: g.n.icon,
            groupCount: g.count
        }
    }

    // Bring listModel in line with the groups of `notifications` (newest
    // first) by the smallest set of removes, moves and inserts.
    function syncNotifications() {
        const incoming = groupsOf(notifications)
        const want = Object.create(null)
        for (let i = 0; i < incoming.length; i++)
            want[incoming[i].gid] = incoming[i].count

        // A group that shrank back to one (or went) closes for good, so it
        // doesn't pop open by itself the next time it grows.
        let stale = false
        for (const gid in expandedGroups) {
            if (!(want[gid] > 1))
                stale = true
        }
        if (stale) {
            const m = {}
            for (const gid in expandedGroups) {
                if (want[gid] > 1)
                    m[gid] = true
            }
            expandedGroups = m
        }

        // Dismissed ones go.
        for (let i = listModel.count - 1; i >= 0; i--) {
            if (!(listModel.get(i).gid in want))
                listModel.remove(i)
        }

        // Then walk down the new order, fixing each row.
        for (let i = 0; i < incoming.length; i++) {
            const g = incoming[i]
            const n = g.n
            if (i < listModel.count && listModel.get(i).gid === g.gid) {
                const row = listModel.get(i)
                if (row.key !== n.key || row.app !== n.app || row.title !== n.title || row.body !== n.body
                        || row.urgency !== g.urgency || row.time !== n.time
                        || row.icon !== n.icon || row.groupCount !== g.count)
                    listModel.set(i, cardData(g))
                continue
            }
            let found = -1
            for (let j = i + 1; j < listModel.count; j++) {
                if (listModel.get(j).gid === g.gid) {
                    found = j
                    break
                }
            }
            if (found >= 0) {
                listModel.move(found, i, 1)
                listModel.set(i, cardData(g))
            } else {
                listModel.insert(i, cardData(g))
            }
        }
    }

    onNotificationsChanged: syncNotifications()
    Component.onCompleted: syncNotifications()

    // "now", "5m", "3h", "2d"
    function ago(ms) {
        const s = Math.max(0, Math.floor((nowMs - ms) / 1000))
        if (s < 60)
            return "now"
        if (s < 3600)
            return Math.floor(s / 60) + "m"
        if (s < 86400)
            return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    // White card with the same outline and hard shadow the pills use.
    // Shifted down again (696, from 586) to clear the now-taller toggles
    // rect above (see its comment) — and shrunk (518, from 573) since
    // that shift used up more of the phone's remaining bottom slack than
    // was actually there, so the card gives back the difference to stay
    // flush with the bottom of the screen instead of running off it.
    // Shifted back up (655, from 696) and grown again (559, from 518) now
    // that the toggles rect above shrank by 41px — same "stay flush with
    // the bottom of the screen" reasoning, just running the other way:
    // the card keeps its own bottom edge exactly where it always was, so
    // the 18px gap above it holds and the extra room goes to the
    // notifications list instead of sitting empty above this card.
    // Pulled up 44px (height 515, from 559): the card's bottom used to sit
    // at y=1214, the very bottom of the 654x1214 face, but the screen
    // itself ends at 1188 (rim 10 + bezel 16 = 26px all round, see
    // PhoneBody.screenInset), so the card ran over the bezel and out of the
    // phone. It now ends at 1170 -- inside the screen with the same ~18px
    // breathing room as above it, and clear of the screen's rounded
    // bottom corners (radius 74).
    Rectangle {
        x: 40 + (mt.quickFlat ? 0 : 5)
        y: 655 + 4 + face.tileExtra
        width: 575
        height: 515 - face.tileExtra
        radius: 41
        color: mt.pLineShadow
        antialiasing: true
        // Under a see-through card it would show through as a dark slab, not a shadow.
        visible: !face.wallOn
    }

    Rectangle {
        id: notificationsCard
        x: 40
        // Rides down with the toggle card above it as button rows are
        // added; it keeps its bottom edge where it always was, so it
        // gets shorter by the same amount (the 18px gap holds).
        y: 655 + face.tileExtra
        width: 575
        height: 515 - face.tileExtra
        radius: 41
        color: face.wallOn ? Qt.alpha(mt.pSurface, face.cardAlpha) : mt.pSurface
        border.width: 3
        border.color: mt.pLine
        clip: true

        readonly property bool empty: face.notifications.length === 0

        // Nothing waiting: a quiet line in the card (emptyNote, below the list)
        // instead of a blank card (issue #41).

        // True for the short animated stretch after "Clear all" is
        // tapped: the cards are sliding themselves out but the data
        // behind them hasn't been wiped yet. Guards the tag against a
        // second tap and the cards against being swiped mid-animation.
        property bool clearing: false

        // Tapped once, from the tag below; every currently-rendered
        // card picks this up (see the delegate's Connections) and
        // starts its own staggered slide-out.
        signal clearAllTriggered()

        // Gives the cards time to actually finish sliding before the
        // data disappears out from under them and the panel closes.
        // Interval covers the longest stagger (index capped at 5) plus
        // one card's own slide duration and a small buffer.
        Timer {
            id: clearAllTimer
            interval: 5 * 35 + 140 + 20
            onTriggered: {
                face.notificationsCleared()
                notificationsCard.clearing = false
                face.panelCloseRequested()
            }
        }

        // Nothing waiting: a muted line, a little cheeky, instead of a blank card. A
        // new one is picked each time the list empties. Placed in the part of the
        // list that is on the monitor (only the top of the phone shows when it is up,
        // so the middle of the whole card can be off-screen), and faded rather than
        // popped so "Clear all"'s slide-out isn't cut short.
        Column {
            id: emptyNote

            readonly property bool shown: notificationsCard.empty && !notificationsCard.clearing
            readonly property var lines: [
                "Nothing here. Suspiciously quiet.",
                "All caught up. Go touch some grass.",
                "No notifications. Even the group chat is asleep.",
                "Inbox zero. The phone is proud of you.",
                "Nothing new. Miku says hi anyway.",
                "Silence. Enjoy it while it lasts."
            ]
            property string line: lines[0]

            function pick() {
                let next = emptyNote.line
                // Not the same one twice in a row.
                while (emptyNote.lines.length > 1 && next === emptyNote.line)
                    next = emptyNote.lines[Math.floor(Math.random() * emptyNote.lines.length)]
                emptyNote.line = next
            }

            onShownChanged: if (shown) pick()
            Component.onCompleted: pick()

            x: (notificationsCard.width - width) / 2
            y: list.y + Math.max(10, (Math.min(list.height, 200) - height) / 2)
            width: 460
            spacing: 6
            opacity: emptyNote.shown ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: 220 }
            }

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "bedtime"
                size: 26
                color: mt.pInkSub
                opacity: 0.8
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: emptyNote.line
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
        }

        // The real list. Text only: which app, when, a bold title, and a
        // line or two underneath.
        WheelScroll { scroller: list }
        ListView {
            id: list
            // Deliberately always visible (not tied to `empty`): hiding
            // it the instant the data went empty is what used to hide
            // every dismiss/clear-all fade before it could play. With
            // nothing in the model it simply draws nothing, and the
            // card's own white background shows through underneath.
            x: 27
            y: 28
            width: 526
            // As tall as its card allows (its height - 28 top - 3 border), but
            // no taller than what's on the monitor: only the top of the
            // phone shows, so a list sized to the whole card would have
            // its lower cards hanging off-screen with nothing to scroll.
            // Cut at the slanted cutoff's lower end so no blank strip
            // shows under the last visible card.
            // Runs all the way down to the monitor edge, so cards scroll
            // under the edge with no empty band across the list. The room
            // the last card needs to come up clear of the edge is scroll
            // margin (bottomMargin below), not a shorter list.
            height: Math.max(95.06, Math.min(notificationsCard.height - 28 - 3,
                                             face.visibleBottomLeft + face.visibleExtra
                                             - (notificationsCard.y + list.y)))
            // The extra height under the monitor edge (visibleExtra) is
            // scroll room too, so the last card can still be brought up
            // fully onto the screen instead of ending under the edge.
            // Scroll room past the last card: the bounce's extra, the slant
            // (the edge is higher on the right) and a pad, so the last card
            // comes up fully onto the screen on both the 2.5D and 2D phone.
            bottomMargin: face.visibleExtra + Math.max(0, face.visibleBottomLeft - face.visibleBottomRight) + face.listBottomPad
            clip: true
            spacing: 7
            boundsBehavior: Flickable.StopAtBounds
            model: listModel
            onContentYChanged: PanelActivity.touch()

            // A new notification: it fades in at the top while the
            // others slide down to make room. Also runs for the cards
            // that are there when the panel is first built, which is
            // why it only touches opacity.
            add: Transition {
                NumberAnimation {
                    property: "opacity"; from: 0; to: 1; duration: 200
                }
            }

            // A dismissed one fades out (a swiped one is already gone)...
            remove: Transition {
                NumberAnimation {
                    property: "opacity"; to: 0; duration: 140
                }
            }

            // ...and the cards under it slide up to close the gap.
            displaced: Transition {
                NumberAnimation {
                    properties: "y"; duration: 240; easing.type: Easing.OutCubic
                }
            }

            // Just a sliver under the last card. It used to be big enough
            // to lift the last card fully clear of the slanted screen
            // edge, but that left a blank strip under it whenever you
            // scrolled to the end. Instead the last card now rests
            // against the edge like the others: its bottom-right corner
            // dips off-screen a little (the tilt), while the text — all
            // on the left, where the edge is lowest — stays fully visible.
            footer: Item {
                width: 526
                height: 6
            }

            // One row per source. A lone notification is a plain card; several
            // from the same source are one card (newest on top, a count
            // pill, a chevron) with a stack peeking out underneath, that
            // opens into a dropdown of every one of them.
            delegate: Item {
                id: row

                required property int index
                required property string gid
                required property var key
                required property string app
                required property string title
                required property string body
                required property double time
                required property int urgency
                required property string icon
                required property int groupCount

                readonly property bool group: groupCount > 1
                readonly property bool open: group && face.expandedGroups[gid] === true
                readonly property real headerH: 95.06

                width: 526
                // Collapsed: the card (plus a sliver of the stack behind it
                // for a group). Open: the card, then its dropdown.
                height: headerH + (open ? 7 + childCol.implicitHeight : (group ? 8 : 0))
                clip: true
                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // The stack behind a collapsed group's card.
                readonly property color peekTone: mt.classic ? Qt.color("#e9e9e9") : Qt.darker(mt.pSurfaceHover, 1.12)

                // 1 while the group is collapsed, 0 once opened: fades the stack
                // out. Kept apart from the drag, so following the card is not
                // delayed by this fade.
                property real peekShow: row.open ? 0 : 1
                Behavior on peekShow { NumberAnimation { duration: 150 } }

                // Both pieces of the stack follow the card (head.slideX /
                // slideOpacity) when it is swiped, springs back, or slides
                // out for "Clear all", so no gray is left behind.
                Rectangle {
                    visible: row.group
                    opacity: row.peekShow * head.slideOpacity
                    x: 9 + head.slideX
                    y: row.headerH - 30
                    width: 508
                    height: 35
                    radius: 16.5
                    color: row.peekTone
                    antialiasing: true
                }

                Rectangle {
                    visible: row.group
                    opacity: row.peekShow * head.slideOpacity
                    x: 18 + head.slideX
                    y: row.headerH - 30
                    width: 490
                    height: 38
                    radius: 16.5
                    color: Qt.darker(row.peekTone, 1.06)
                    antialiasing: true
                }

                NotificationCard {
                    id: head

                    key: row.key
                    app: row.app
                    // Open, the card stops repeating the newest one (the
                    // dropdown lists it) and just says what it holds.
                    title: row.open ? row.groupCount + " notifications" : row.title
                    body: row.open ? "Swipe to clear them all" : row.body
                    time: row.time
                    urgency: row.urgency
                    icon: row.icon
                    agoText: face.ago(row.time)
                    groupCount: row.groupCount
                    expanded: row.open
                    blocked: notificationsCard.clearing
                    clearIndex: row.index

                    // A lone card: dismiss it. A group: swiping clears every
                    // notification from that source.
                    onDismissed: {
                        if (row.group)
                            face.notificationsDismissed(face.groupKeys(row.gid))
                        else
                            face.notificationDismissed(row.key)
                    }
                    onToggled: face.toggleGroup(row.gid)
                    onActivated: face.notificationActivated(row.key)

                    Connections {
                        target: notificationsCard
                        function onClearAllTriggered() { head.clearOut() }
                    }
                }

                // The dropdown: every notification of the group, each one
                // dismissable on its own.
                Column {
                    id: childCol
                    x: 14
                    y: row.headerH + 7
                    spacing: 7
                    opacity: row.open ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    Repeater {
                        model: row.open ? face.groupItems(row.gid) : []

                        delegate: NotificationCard {
                            required property var modelData

                            key: modelData.key
                            app: modelData.app
                            title: modelData.title
                            body: modelData.body
                            time: modelData.time
                            urgency: modelData.urgency
                            icon: modelData.icon
                            agoText: face.ago(modelData.time)
                            cardWidth: 512
                            blocked: notificationsCard.clearing
                            onDismissed: face.notificationDismissed(modelData.key)
                            onActivated: face.notificationActivated(modelData.key)
                        }
                    }
                }
            }
        }

        // Scrollbar for the real list (only when there's more than fits)
        Rectangle {
            visible: !notificationsCard.empty && list.visibleArea.heightRatio < 1
            // The track ends at the screen's edge on the right (where
            // the scrollbar is), a little above the list's own bottom.
            readonly property real track: list.height - face.visibleExtra - Math.max(0, face.visibleBottomLeft - face.visibleBottomRight)
            x: 563
            y: 28 + list.visibleArea.yPosition * track
            width: 6
            height: Math.max(30, list.visibleArea.heightRatio * track)
            radius: 3
            color: mt.pSurfaceRing
            antialiasing: true
        }
        antialiasing: true
    }

    // Edit mode's add tray: covers the notifications card (same spot, same
    // size) while editing, listing the buttons that aren't on the panel.
    // Tap one to add it (small — the resize badge makes it big); removed
    // buttons come back here.
    Rectangle {
        id: editTray
        x: 40
        y: notificationsCard.y
        width: 575
        height: notificationsCard.height
        // How much of the tray is on the monitor. Only the top of the phone
        // shows, so (as with the notification list) anything below the
        // slanted cutoff is off-screen: the lower of its two ends is used
        // because the tray spans the whole width.
        readonly property real shownH: Math.max(0, Math.min(height,
            Math.min(face.visibleBottomLeft, face.visibleBottomRight) - y))
        // How far down the tray the monitor edge reaches at most: the lower end of
        // the slanted cutoff plus the pull-out bounce's extra (the same reach the
        // notification list runs to). shownH is the part that is always on screen.
        readonly property real reachH: Math.max(0, Math.min(height,
            face.visibleBottomLeft + face.visibleExtra - y))
        radius: 41
        color: mt.pSurface
        border.width: 3
        border.color: mt.pLine
        clip: true
        opacity: face.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        // Nothing behind the tray (the notification cards) should react
        // while it's up.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        // Columns: the most buttons a row may hold, 1-5, whatever their size.
        // Five is the old layout (widths never change — fewer columns just
        // wrap sooner). A count that would make the grid too tall for the
        // current buttons is dimmed and does nothing until one is removed.
        Item {
            id: columnsRow
            x: 27
            y: 30
            width: 520
            height: 44

            Text {
                id: columnsLabel
                anchors.verticalCenter: parent.verticalCenter
                text: "Columns"
                color: mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 18
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }

            Row {
                anchors.left: columnsLabel.right
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: [1, 2, 3, 4, 5]

                    delegate: Rectangle {
                        id: chip
                        required property int modelData

                        readonly property bool current: face.tileColumns === modelData
                        readonly property bool allowed: face.canColumns(modelData)

                        width: 46
                        height: 40
                        radius: 20
                        color: chip.current ? mt.accentMint : mt.pSurfaceDivider
                        border.width: 3
                        border.color: mt.pLine
                        opacity: chip.allowed || chip.current ? 1 : 0.4
                        antialiasing: true

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: chip.modelData
                            color: chip.current ? mt.colBorder : mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: chip.allowed && !chip.current
                            cursorShape: Qt.PointingHandCursor
                            onClicked: face.tileColumnsRequested(chip.modelData)
                        }
                    }
                }
            }
        }

        // The buttons that aren't on the panel, five to a row (100px each, 4px
        // apart = 516 of the tray's 520px content width). There are more of
        // them than fit in the tray at once, so the list scrolls: mouse wheel,
        // or drag it. When the "panel is full" note is showing, the list stops
        // above it instead of running underneath.
        WheelScroll { scroller: trayScroll }
        Flickable {
            id: trayScroll
            x: 27
            y: columnsRow.y + columnsRow.height + 10
            width: 520
            // Runs all the way down to the monitor edge (editTray.reachH), like the
            // notification list: the buttons scroll under the edge instead of being
            // cut by an invisible line with the picture showing under them. The
            // room the last row needs to come up clear of the edge is scroll margin
            // (bottomMargin), not a shorter list. With the "panel is full" note up,
            // the list still stops above the note.
            readonly property bool noteUp: face.unplacedTiles.length > 0 && !face.canAdd
            height: Math.max(0, (noteUp ? editTray.shownH - 68 : editTray.reachH - 14) - y)
            bottomMargin: noteUp ? 0 : Math.max(0, editTray.reachH - editTray.shownH) + face.listBottomPad
            onContentYChanged: PanelActivity.touch()
            contentWidth: width
            contentHeight: trayFlow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Flow {
                id: trayFlow
                width: trayScroll.width
                spacing: 4

                Repeater {
                    model: face.unplacedTiles

                    delegate: Item {
                        required property string modelData

                        width: 100
                        height: 118
                        opacity: face.canAdd ? 1 : 0.4

                        QuickToggle {
                            flatShadow: mt.quickFlat
                            kind: "round"
                            anchors.horizontalCenter: parent.horizontalCenter
                            hoverLights: face.canAdd
                            enabled: face.canAdd
                            icon: face.tileIcon(modelData)
                            onClicked: face.tileAddRequested(modelData)
                        }

                        // Two lines, so "Cloudflare WARP" / "On-Screen
                        // Keyboard" / "Music Recognition" read in full.
                        Text {
                            y: 80
                            x: 2
                            width: parent.width - 4
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 0.9
                            text: face.tileName(modelData)
                            color: mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }
                    }
                }
            }
        }

        // Scrollbar for the list (only when there's more than fits)
        Rectangle {
            visible: trayScroll.visibleArea.heightRatio < 1
            x: 555
            y: trayScroll.y + trayScroll.visibleArea.yPosition * trayScroll.height
            width: 6
            height: Math.max(30, trayScroll.visibleArea.heightRatio * trayScroll.height)
            radius: 3
            color: mt.pSurfaceRing
            antialiasing: true
        }

        Text {
            visible: face.unplacedTiles.length === 0
            x: 27
            y: columnsRow.y + columnsRow.height + 24
            width: 520
            wrapMode: Text.WordWrap
            text: "Every button is on the panel. Remove one to see it here."
            color: mt.pInk
            opacity: 0.67
            font.family: mt.fontFamily
            font.pixelSize: 18
        }

        Text {
            visible: face.unplacedTiles.length > 0 && !face.canAdd
            x: 27
            y: editTray.shownH - 60
            width: 520
            wrapMode: Text.WordWrap
            text: "The panel is full. Remove a button to make room."
            color: mt.pInk
            opacity: 0.67
            font.family: mt.fontFamily
            font.pixelSize: 18
        }
    }

    // The "Notifications" tag sitting on the card's top edge. With
    // something in the list, hovering it turns it into "Clear all".
    // Shifted up the same 41px as the card itself, above, so it still
    // sits right on its top edge.
    Rectangle {
        id: tag

        x: 212
        y: 639 + face.tileExtra
        width: 229
        height: 31
        radius: 27
        color: tagArea.containsMouse && !notificationsCard.empty && !notificationsCard.clearing ? mt.accentMint : mt.pSurface
        border.width: 3
        border.color: mt.pLine

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Text {
            anchors.centerIn: parent
            text: face.editing ? "Add buttons"
                : (tagArea.containsMouse && !notificationsCard.empty && !notificationsCard.clearing ? "Clear all" : "Notifications")
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 20
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        MouseArea {
            id: tagArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !face.editing && !notificationsCard.empty && !notificationsCard.clearing
            cursorShape: notificationsCard.empty ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                // Cards slide themselves out first; clearAllTimer (see
                // notificationsCard) does the real clear and closes the
                // panel once they've actually finished.
                notificationsCard.clearing = true
                notificationsCard.clearAllTriggered()
                clearAllTimer.restart()
            }
        }
        antialiasing: true
    }

    // ===== Wi-Fi / Bluetooth dialogs =====
    NetworkDialog {
        id: networkDialog
        open: face.networkDialogOpen
        networks: face.wifiNetworks
        scanning: face.wifiScanning
        manualScanning: face.wifiManualScanning
        connectingSsid: face.wifiConnectingSsid
        errorText: face.wifiConnectError
        onCloseRequested: face.networkDialogOpen = false
        onScanRequested: face.wifiScanRequested()
        onAdvancedRequested: face.wifiAdvancedRequested()
        onConnectRequested: (ssid, password) => face.wifiConnectRequested(ssid, password)
        onDisconnectRequested: ssid => face.wifiDisconnectRequested(ssid)
    }

    BluetoothDialog {
        id: bluetoothDialog
        open: face.bluetoothDialogOpen
        devices: face.bluetoothDevices
        scanning: face.bluetoothScanning
        manualScanning: face.bluetoothManualScanning
        connectingAddress: face.bluetoothConnectingAddress
        errorText: face.bluetoothConnectError
        onCloseRequested: face.bluetoothDialogOpen = false
        onScanRequested: face.bluetoothScanRequested()
        onAdvancedRequested: face.bluetoothAdvancedRequested()
        onConnectRequested: address => face.bluetoothConnectRequested(address)
        onDisconnectRequested: address => face.bluetoothDisconnectRequested(address)
    }

    KeepAwakeDialog {
        id: keepAwakeDialog
        open: face.keepAwakeDialogOpen
        mode: face.keepAwakeMode
        onCloseRequested: face.keepAwakeDialogOpen = false
        onModeSelected: m => face.keepAwakeModeRequested(m)
    }

    VolumeMixerDialog {
        id: volumeMixerDialog
        open: face.audioDialogKind !== ""
        kind: face.audioDialogShownKind === "microphone" ? "microphone" : "speaker"
        title: face.audioDialogShownKind === "microphone" ? "Microphone" : "Speaker"
        deviceCaption: face.audioDialogShownKind === "microphone" ? "Input" : "Output"
        devices: face.audioDialogShownKind === "microphone" ? face.microphoneDevices : face.speakerDevices
        streams: face.audioDialogShownKind === "microphone" ? face.microphoneStreams : face.speakerStreams
        scanning: face.audioDevicesScanning
        manualScanning: face.audioDevicesManualScanning
        selectingDeviceId: face.audioDeviceSelectingId
        onCloseRequested: face.audioDialogKind = ""
        onScanRequested: face.audioDeviceScanRequested()
        onDeviceSelected: id => {
            if (face.audioDialogShownKind === "microphone")
                face.microphoneDeviceSelected(id)
            else
                face.speakerDeviceSelected(id)
        }
        onStreamVolumeChanged: (id, value) => {
            if (face.audioDialogShownKind === "microphone")
                face.microphoneStreamVolumeChanged(id, value)
            else
                face.speakerStreamVolumeChanged(id, value)
        }
        onStreamMuteToggled: (id, muted) => {
            if (face.audioDialogShownKind === "microphone")
                face.microphoneStreamMuteToggled(id, muted)
            else
                face.speakerStreamMuteToggled(id, muted)
        }
        onStreamDragStarted: id => {
            if (face.audioDialogShownKind === "microphone")
                face.microphoneStreamDragStarted(id)
            else
                face.speakerStreamDragStarted(id)
        }
        onStreamDragEnded: id => {
            if (face.audioDialogShownKind === "microphone")
                face.microphoneStreamDragEnded(id)
            else
                face.speakerStreamDragEnded(id)
        }
    }

    NightLightDialog {
        id: nightLightDialog
        open: face.nightLightDialogOpen
        nightOn: face.nightLightOn
        temperature: face.nightLightTemperature
        autoOn: face.nightLightAuto
        autoFrom: face.nightLightAutoFrom
        autoTo: face.nightLightAutoTo
        onCloseRequested: face.nightLightDialogOpen = false
        onToggleRequested: face.nightLightToggled()
        onTemperatureMoved: kelvin => face.nightLightTemperatureMoved(kelvin)
        onAutoRequested: on => face.nightLightAutoRequested(on)
        onScheduleRequested: (from, to) => face.nightLightScheduleRequested(from, to)
    }

    // ===== Power menu scrim =====
    PowerMenuScrim {
        id: powerScrim
        open: face.powerMenuOpen
        onDismissRequested: face.powerMenuOpen = false
    }

    // ===== heads-up =====
    Item {
        id: alertCard

        readonly property var e: face.alertEntry
        readonly property bool critical: e !== null && e.urgency === 2
        // The shell's own notifications (a "material:<glyph>" icon: screenshot,
        // recording, timer ...) wear the attribute badge instead of a white disc.
        readonly property bool shellIcon: e !== null && e.icon.startsWith("material:")

        // 0 = away, 1 = resting. Drives the slide, the fade and the scale.
        property real reveal: face.alertShown ? 1 : 0
        // A short extra pop when a second notification lands while the
        // first one's still up.
        property real pop: 0

        x: 47
        y: 84 - (1 - reveal) * 44
        width: 560
        height: 112
        visible: reveal > 0.001
        opacity: Math.min(1, reveal * 1.6)
        scale: (0.94 + 0.06 * reveal) * (1 + 0.04 * pop)
        transformOrigin: Item.Top

        Behavior on reveal {
            NumberAnimation {
                duration: face.alertShown ? 300 : 200
                easing.type: face.alertShown ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.4
            }
        }

        // Only a *changed* card needs the pop; the first one arrives with
        // the slide already.
        Connections {
            target: face
            function onAlertEntryChanged() {
                if (face.alertShown && alertCard.reveal > 0.5)
                    popAnim.restart()
            }
        }

        NumberAnimation {
            id: popAnim
            target: alertCard
            property: "pop"
            from: 1
            to: 0
            duration: 340
            easing.type: Easing.OutQuad
        }

        // Same bookkeeping as the list's swipe: tell PhoneBody something
        // on the screen is animating.
        onYChanged: PanelActivity.touch()

        // Hard shadow
        Rectangle {
            x: mt.quickFlat ? 0 : 5
            y: 4
            width: parent.width
            height: parent.height
            radius: 34
            color: mt.pLineShadow
            antialiasing: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 34
            color: mt.pSurface
            border.width: alertCard.critical ? 5 : 3
            border.color: mt.pLine
            antialiasing: true
        }

        Item {
            id: alertIcon
            x: 22
            width: 64
            height: 64
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                visible: !alertCard.shellIcon
                anchors.fill: parent
                radius: width / 2
                color: mt.pSurface
                antialiasing: true
            }

            ShellBadge {
                anchors.centerIn: parent
                size: 58
                visible: alertCard.shellIcon
                glyph: alertCard.shellIcon ? alertCard.e.icon.substring(9) : ""
            }

            Image {
                anchors.centerIn: parent
                width: parent.width
                height: width
                visible: alertCard.e !== null && alertCard.e.icon !== "" && !alertCard.e.icon.startsWith("material:")
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(Math.ceil(width * 3), Math.ceil(width * 3))
                source: alertCard.e !== null && !alertCard.e.icon.startsWith("material:") ? alertCard.e.icon : ""
            }

            MaterialIcon {
                anchors.centerIn: parent
                size: parent.width - 10
                visible: alertCard.e === null || alertCard.e.icon === ""
                name: "notifications_active"
            }
        }

        Text {
            x: 104
            y: 12
            width: 340
            elide: Text.ElideRight
            text: alertCard.e !== null ? alertCard.e.app : ""
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 15
            font.weight: Font.Medium
        }

        Text {
            x: parent.width - 26 - width
            y: 12
            width: 70
            horizontalAlignment: Text.AlignRight
            text: "now"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 15
            font.weight: Font.Medium
        }

        Text {
            x: 104
            y: 31
            width: 434
            elide: Text.ElideRight
            text: alertCard.e !== null ? alertCard.e.title : ""
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 23
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Text {
            x: 104
            y: 61
            width: 434
            visible: text !== ""
            text: alertCard.e !== null ? alertCard.e.body : ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.92
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 17
        }

        // Resting the pointer on the card brings the whole phone up (the same as
        // clicking it: alertActivated() -> QuickPanel.claim()). After a second, not a
        // beat: the pointer on its way to swipe the phone away or right-click it
        // (QuickPanel.qml, alertTouch) must have time to do that first; it used to be
        // 180 ms, which opened the phone under almost anyone aiming at it.
        Timer {
            id: hoverOpen
            interval: 1000
            onTriggered: {
                if (face.alertShown)
                    face.alertActivated()
            }
        }

        // Left click: the app's own action for it (Discord: the message), or keep the
        // phone up when it has none. Middle click: keep the phone up. Right click: dismiss.
        MouseArea {
            anchors.fill: parent
            enabled: face.alertShown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse)
                    hoverOpen.restart()
                else
                    hoverOpen.stop()
            }
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && alertCard.e !== null)
                    face.alertDismissRequested(alertCard.e.key)
                else if (mouse.button === Qt.LeftButton && alertCard.e !== null)
                    face.alertClicked(alertCard.e.key)
                else
                    face.alertActivated()
            }
        }
    }
}
