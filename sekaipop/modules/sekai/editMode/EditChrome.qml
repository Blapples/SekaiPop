import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/PluginForm.js" as PF

// What a desktop widget wears while Edit Desktop is on. Drop one inside the
// widget's card (the Item that is dragged around) and fill in the properties;
// it draws nothing at all the rest of the time.
//
//   EditChrome {
//       id: chrome
//       widgetId: "clock"          // the id EditMode.widgetList uses
//       target: card
//       roomW: win.roomW
//       roomH: win.roomH
//       screenName: win.screen ? win.screen.name : ""
//       onMoved: SomeService.setPosition(card.x, card.y)
//       onRemoveRequested: SomeService.setShown(false)
//   }
//
// What you can do to a widget on the card:
//
//   left drag    move it anywhere (the shield below does the moving)
//   left click   EDIT it: the widget is "selected" (EditMode.editTarget). The
//                shield steps aside, so the widget works as it does on the
//                normal desktop: the clock's double-click and style button, the
//                To-Do's tasks, the avatar's pop. The widget's own drag area
//                moves it meanwhile (`chrome.selected` is what it checks).
//                Click the bare card, press Esc, or pick another widget to stop.
//   right click  remove it. It goes back on the shelf; click it there to bring
//                it back.
//
// What it wears:
//
// - a cyan outline round the card (mint and thicker while it is being
//   edited), with a mint diamond on every corner (the notes of the Sekai
//   rhythm lanes) that perk up under the pointer
// - a small tag on the top edge: "CLICK TO EDIT" under the pointer, "EDITING"
//   while it is selected; a selected plugin with settings or secrets gets a
//   Settings key beside it, which opens Settings > Desktop > Plugins on it
// - a flash of the outline when the shelf points at it (EditMode.ping)
//
// z: 15 on purpose: above a card's content and its own drag area, but under
// the hover button the clock keeps on its corner (z: 20).
//
// The alignment grid (services/EditGrid.qml, drawn by EditGuides.qml) hangs
// off this too, because this is the one place that knows where the card is
// and when it is being moved:
//
// - it tells EditGrid where its card is (`report()`), so every widget knows
//   where the others are
// - while the card is dragged (by the shield below, or by the widget's own drag
//   area: that one sets `chrome.ownDrag`) it pulls the card onto the grid and
//   onto the other widgets' lines (`snapCard()`), and says when the drag starts
//   and ends, so the grid appears and the confirmation plays on release
// - when a card that was just dropped lines up with this one, this one's
//   outline flares
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string widgetId: ""
    property Item target: null
    property real roomW: 0
    property real roomH: 0
    property string screenName: ""

    signal moved()
    signal removeRequested()

    readonly property bool editing: EditMode.active && EditMode.editing(root.screenName)

    // This widget is the one being edited (see the header).
    readonly property bool selected: root.editing && root.widgetId !== "" && EditMode.editTarget === root.widgetId

    // True while the card is being dragged by the shield below. The widgets
    // use it to keep their own re-placing from fighting the drag.
    readonly property bool dragging: shield.drag.active

    // The widget's own drag area (the one that works while it is selected) sets
    // this, so a drag that is not the shield's is snapped and confirmed too.
    property bool ownDrag: false

    // The card is being moved, by whichever of the two.
    readonly property bool gripped: root.editing && (shield.drag.active || root.ownDrag)

    // On the card being edited: shown, and on this monitor.
    readonly property bool present: root.editing && root.target !== null
        && root.widgetId !== "" && EditMode.widgetOn(root.widgetId)

    // The card is being edited or moved: its window goes up a layer (the widgets
    // bind `WlrLayershell.layer` to this) and comes back down when it is let go.
    // Compositors put a surface that changes layer on top of that layer, so the
    // widget edited last ends up in front of the other widgets, and stays there.
    readonly property bool raised: root.selected || root.gripped

    readonly property bool hot: root.editing && !root.selected && (hover.hovered || shield.pressed)

    z: 15
    anchors.fill: parent

    // On / off is a pop, not a fade: the whole outfit springs up from the
    // card's centre with an overshoot, and is swallowed (a straight shrink,
    // nothing before it) when editing ends. Two fixed animations started from
    // onEditingChanged, so the way out can never pick up the way in's easing.
    property real pop: 0
    visible: root.pop > 0.001
    scale: Math.max(0, root.pop)
    transformOrigin: Item.Center

    onEditingChanged: {
        if (root.editing) {
            outfitOut.stop()
            outfitIn.restart()
        } else {
            outfitIn.stop()
            outfitOut.restart()
        }
    }

    Component.onCompleted: {
        root.pop = root.editing ? 1 : 0
        root.report()
    }

    // ===== the alignment grid =====
    // Widget + monitor: the same widget can be on several monitors (see EditGrid.qml).
    readonly property string gridId: root.widgetId === "" ? "" : root.widgetId + "@" + root.screenName

    function report() {
        const t = root.target
        if (!t)
            return
        // (a monitor that is not being edited reports nothing)
        if (EditMode.active && !root.editing)
            return
        EditGrid.report(root.gridId, t.x, t.y, t.width, t.height, root.present)
    }

    // Pulls the card to where EditGrid says it should go. Runs on every change
    // of the card's x / y; the card's own writes below don't re-enter it (and
    // snapping a snapped position changes nothing, see EditGridMath.js).
    property bool snapping: false

    function snapCard() {
        const t = root.target
        if (!t || root.snapping)
            return
        if (root.gripped) {
            root.snapping = true
            const s = EditGrid.snap(root.gridId, t.x, t.y, t.width, t.height, root.roomW, root.roomH)
            if (s.x !== t.x)
                t.x = s.x
            if (s.y !== t.y)
                t.y = s.y
            root.snapping = false
        }
        root.report()
    }

    onPresentChanged: root.report()

    onGrippedChanged: {
        const t = root.target
        if (!t)
            return
        if (root.gripped) {
            root.report()
            EditGrid.begin(root.gridId)
            root.snapCard()
        } else {
            EditGrid.end(root.gridId, t.x, t.y, t.width, t.height, root.roomW, root.roomH)
            // It lined up with something: the dropped card flashes too.
            if (Object.keys(EditGrid.matchedIds).length > 0 && root.editing)
                flareAnim.restart()
            root.report()
        }
    }

    Connections {
        target: root.target

        function onXChanged() { root.snapCard() }
        function onYChanged() { root.snapCard() }
        function onWidthChanged() { root.report() }
        function onHeightChanged() { root.report() }
    }

    // Somebody was just dropped on a line with this card (or the same size as it).
    Connections {
        target: EditGrid

        function onMatchSerialChanged() {
            if (root.editing && root.gridId !== "" && EditGrid.matchedIds[root.gridId] === true)
                flareAnim.restart()
        }
    }

    NumberAnimation {
        id: outfitIn
        target: root
        property: "pop"
        to: 1
        duration: 420
        easing.type: Easing.OutBack
        easing.overshoot: 2.2
    }

    NumberAnimation {
        id: outfitOut
        target: root
        property: "pop"
        to: 0
        duration: 280
        easing.type: Easing.InCubic
    }

    // The shelf pointing at this widget: the outline flares and fades.
    property real flare: 0

    Connections {
        target: EditMode

        function onPingSerialChanged() {
            if (root.editing && EditMode.pingId === root.widgetId && root.widgetId !== "")
                flareAnim.restart()
        }
    }

    SequentialAnimation {
        id: flareAnim
        NumberAnimation { target: root; property: "flare"; to: 1; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "flare"; to: 0; duration: 650; easing.type: Easing.OutCubic }
    }

    HoverHandler {
        id: hover
        enabled: root.editing
        // Non-blocking: KeysOnPoint (on the window) must still hear the pointer over a card
        // that is selected for editing, or its text boxes could not take the keyboard.
        blocking: false
    }

    // ===== outline =====
    Rectangle {
        anchors.fill: parent
        anchors.margins: -12 - root.flare * 8
        radius: mt.radiusOuter + 12 + root.flare * 8
        color: "transparent"
        border.width: 6
        border.color: mt.accentMint
        opacity: root.gripped ? 0.34 : (root.selected ? 0.28 : root.flare * 0.6)
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -6
        radius: mt.radiusOuter + 6
        color: "transparent"
        border.width: root.selected || root.gripped ? 4 : 3
        border.color: root.selected || root.gripped || root.flare > 0.05 ? mt.accentMint : mt.accentCyan
        antialiasing: true

        Behavior on border.color {
            ColorAnimation { duration: 140 }
        }
    }

    // ===== corner notes =====
    Repeater {
        model: 4

        Rectangle {
            required property int index

            readonly property bool atRight: index === 1 || index === 3
            readonly property bool atBottom: index === 2 || index === 3

            width: 13
            height: 13
            radius: 3
            rotation: 45
            color: root.selected ? mt.accentCyan : mt.accentMint
            border.width: 2
            border.color: mt.colBorder
            antialiasing: true
            x: (atRight ? root.width + 6 : -6) - width / 2
            y: (atBottom ? root.height + 6 : -6) - height / 2

            scale: !root.editing ? 0.4 : (root.hot || root.selected ? 1.35 : 1)
            Behavior on scale {
                NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
            }
        }
    }

    // ===== the tag on the top edge =====
    Item {
        id: tag
        readonly property bool want: root.editing && (root.hot || root.selected)

        width: tagPill.width
        height: tagPill.height
        // centred together with the Settings key, when there is one
        x: (root.width - width - (settingsKey.want ? settingsKey.width + 6 : 0)) / 2
        // Fully above the card's edge, so a snapshot of the card (the shelf's
        // picture, EditPreview.qml) never contains it.
        y: -height - 6
        scale: tag.want ? 1 : 0
        visible: scale > 0.01
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
        }

        Pill {
            id: tagPill
            width: tagRow.width + 22
            height: 28
            cornerRadius: 10
            ringWidth: 3
            fillColor: root.selected ? mt.accentMint : mt.chipFill

            Row {
                id: tagRow
                anchors.centerIn: parent
                spacing: 5

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.selected ? "edit" : "touch_app"
                    size: 14
                    weight: 700
                    color: root.selected ? mt.colBorder : mt.chipInk
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selected ? "EDITING" : "CLICK TO EDIT"
                    color: root.selected ? mt.colBorder : mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 0.8
                }
            }
        }
    }

    // ===== a plugin's Settings key, beside the tag =====
    // Only a plugin widget with something to set has one (PluginForm.hasForm).
    Item {
        id: settingsKey
        readonly property var plugin: PluginService.isPluginId(root.widgetId) ? PluginService.pluginOf(root.widgetId) : null
        readonly property bool want: root.selected && plugin !== null && PF.hasForm(plugin)

        width: keyPill.width
        height: keyPill.height
        x: tag.x + tag.width + 6
        y: tag.y + (tag.height - height) / 2
        scale: want ? (keyArea.pressed ? 0.94 : 1) : 0
        visible: scale > 0.01

        Behavior on scale {
            NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
        }

        Pill {
            id: keyPill
            width: keyRow.width + 26
            height: 32 + mt.shadowOffset
            cornerRadius: 11
            ringWidth: 0
            fillColor: keyArea.containsMouse ? mt.pSurfaceHover : mt.pSurface

            Row {
                id: keyRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -mt.shadowOffset / 2
                spacing: 7

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "tune"
                    size: 16
                    weight: 700
                    color: mt.colBorder
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Settings"
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Black
                    font.styleName: mt.fontStyleBold
                }
            }
        }

        MouseArea {
            id: keyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PluginService.askSettings(root.widgetId, root.screenName)
        }
    }

    // ===== the drag shield =====
    MouseArea {
        id: shield
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        enabled: root.editing && root.target !== null && !root.selected
        cursorShape: shield.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        drag.target: root.target
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 0
        drag.maximumX: Math.max(0, root.roomW - (root.target ? root.target.width : 0))
        drag.minimumY: 0
        drag.maximumY: Math.max(0, root.roomH - (root.target ? root.target.height : 0))

        // (Qt does not send `clicked` for a press that turned into a drag.)
        onClicked: EditMode.select(root.widgetId)

        drag.onActiveChanged: {
            if (!drag.active)
                root.moved()
        }
    }

    // ===== right click: remove =====
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        enabled: root.editing
        onClicked: {
            if (EditMode.editTarget === root.widgetId)
                EditMode.select("")
            root.removeRequested()
        }
    }
}
