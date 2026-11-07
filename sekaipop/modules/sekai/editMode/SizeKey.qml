import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The size key a desktop card wears on its top-right corner while it is selected in Edit
// Desktop (click the card there): one press flips it between FULL and 2 x 2, and a chip
// names the size it just became. It is the clock's design key, made reusable: same mint to
// cyan key, same pop, same place. There is no such key on the normal desktop.
//
//   SizeKey {
//       shown: chrome.selected
//       small: CalendarCardService.small
//       onToggled: CalendarCardService.toggleSize()
//   }
//
// The weather card wears the same key for its style (Classic / Minimal), with `icon` and `label`
// set; see WeatherCardWidget.qml. A card with three sizes (FULL / 2 x 2 / 1 x 1) sets `label` too
// and passes `small: <it is the 1 x 1 now>`, so the arrow points the way the next press goes.
//
// Put it inside the card (the Item that is dragged around). `z: 20` keeps it above
// EditChrome (z: 15) and the card's content, so it wins its own clicks; while it is hidden
// its MouseArea is off, so it never eats a click meant for the card.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property bool shown: false
    // The card is the 2 x 2 size right now (the key then offers FULL, and the other way round).
    property bool small: false
    // Optional: make it some other key than the size one (the weather card's style key).
    // `icon` replaces the open / close arrows; `label` replaces the chip's "SIZE  ..." text
    // and the chip flashes whenever it changes. Both empty = the size key, as it always was.
    property string icon: ""
    property string label: ""
    // Which place on the corner it takes: 0 is the top one; a card with two keys (the weather
    // card: style and size) puts the second at 1, 40 px lower.
    property int row: 0

    signal toggled()

    z: 20
    width: 30
    height: 34
    x: root.parent ? root.parent.width - root.width + 10 : 0
    y: -12 + root.row * 40
    visible: root.opacity > 0.01
    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.6
    transformOrigin: Item.Center

    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    Behavior on scale {
        NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }

    // The chip shows for a moment after a press (and while the pointer is on the key), so
    // you can read which size you ended up on.
    onSmallChanged: {
        if (root.shown)
            labelTimer.restart()
    }

    onLabelChanged: {
        if (root.shown)
            labelTimer.restart()
    }

    Timer {
        id: labelTimer
        interval: 1400
    }

    Pill {
        anchors.fill: parent
        cornerRadius: 10
        ringWidth: 3
        pressed: keyArea.pressed
        fillGradient: Gradient {
            GradientStop { position: 0.0; color: mt.accentMint }
            GradientStop { position: 1.0; color: mt.accentCyan }
        }

        MaterialIcon {
            anchors.centerIn: parent
            name: root.icon !== "" ? root.icon : (root.small ? "open_in_full" : "close_fullscreen")
            size: 18
            weight: 600
            color: mt.colBorder
        }
    }

    Pill {
        id: nameChip
        visible: root.shown && (keyArea.containsMouse || labelTimer.running)
        x: -nameChip.width - 4
        y: 2
        width: nameText.implicitWidth + 24
        height: 30
        cornerRadius: 10
        ringWidth: 3
        fillColor: mt.chipFill

        Text {
            id: nameText
            anchors.centerIn: parent
            text: root.label !== "" ? root.label : "SIZE  " + (root.small ? "2 x 2" : "FULL")
            color: mt.chipInk
            font.family: mt.fontFamily
            font.pixelSize: 11
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }
    }

    MouseArea {
        id: keyArea
        anchors.fill: parent
        // An invisible key must not eat clicks meant for the card.
        enabled: root.shown
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
