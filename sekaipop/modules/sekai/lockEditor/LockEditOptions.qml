import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCanvasModel.js" as LM
import "../../common/functions/LockEditMath.js" as EM

// The middle-right of the editor's shelf: what you can change about the selected widget.
//
//   nothing selected   a line saying how to start
//   a widget           its name and a remove key, its SIZE (- / + / 100%), and one row per
//                      option it has (LockCanvasModel.describe): choices for a list, ON / OFF
//                      for a switch, a box for words, a Choose key for a picture
//   the password block it can move but not be removed or resized; a key puts it back in the middle
//
// Everything goes through LockEditService, so each change is checked by the model, can be
// undone, and is saved. `typing` is true while the words box has the keyboard (the stage
// then leaves the arrow keys and Delete alone).
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    readonly property string uid: LockEditService.selected
    readonly property bool isCore: root.uid === "core"
    readonly property var spec: root.isCore ? null : LockEditService.item(root.uid)
    readonly property var info: root.spec ? LM.describe(root.spec.kind) : null
    // True while the words box has the keyboard.
    property bool typing: false
    onUidChanged: root.typing = false

    // A small key: an icon or a few letters. Ring 3, like the shelf's other small keys.
    component MiniKey: Item {
        id: mk

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string icon: ""
        property string label: ""
        property bool dim: false

        signal activated()

        implicitWidth: label !== "" && icon === "" ? Math.max(40, mkText.implicitWidth + 22) : 40
        implicitHeight: 32
        width: implicitWidth
        height: implicitHeight
        opacity: mk.dim ? 0.45 : 1

        Pill {
            anchors.fill: parent
            cornerRadius: 10
            ringWidth: 3
            shadowDy: 3
            pressed: mkArea.pressed && !mk.dim
            fillColor: mkArea.containsMouse && !mk.dim ? mk.mt.pSurfaceHover : mk.mt.pSurface

            MaterialIcon {
                visible: mk.icon !== ""
                anchors.centerIn: parent
                name: mk.icon
                size: 18
                weight: 600
                color: mk.mt.pInk
            }

            Text {
                id: mkText
                visible: mk.icon === ""
                anchors.centerIn: parent
                text: mk.label
                color: mk.mt.pInk
                font.family: mk.mt.fontFamily
                font.pixelSize: 12
                font.weight: Font.ExtraBold
                font.styleName: mk.mt.fontStyleBold
            }
        }

        MouseArea {
            id: mkArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !mk.dim
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mk.activated()
        }
    }

    // One row: the name of the setting, then its control.
    component Row2: Item {
        id: rw

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string title: ""
        default property alias control: slot.data

        height: 32

        Text {
            width: 84
            anchors.verticalCenter: parent.verticalCenter
            text: rw.title
            elide: Text.ElideRight
            color: rw.mt.pInkSub
            font.family: rw.mt.fontFamily
            font.pixelSize: 12
            font.weight: Font.ExtraBold
            font.styleName: rw.mt.fontStyleBold
            font.letterSpacing: 1
        }

        Item {
            id: slot
            x: 92
            width: rw.width - 92
            height: rw.height
        }
    }

    // ===== nothing selected =====
    Column {
        visible: root.uid === ""
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        spacing: 6

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Click a widget on the card to change it."
            color: root.mt.pInk
            font.family: root.mt.fontFamily
            font.pixelSize: 14
            font.weight: Font.ExtraBold
            font.styleName: root.mt.fontStyleBold
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Click a key to the left to add one, or drag it onto the card."
            color: root.mt.pInkSub
            font.family: root.mt.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    // ===== the password block =====
    Column {
        visible: root.isCore
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        spacing: 8

        Row {
            spacing: 8

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: 20
                weight: 600
                color: root.mt.pInk
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "PASSWORD BLOCK"
                color: root.mt.pInk
                font.family: root.mt.fontFamily
                font.pixelSize: 15
                font.weight: Font.ExtraBold
                font.styleName: root.mt.fontStyleBold
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Always on the lockscreen, so it can't be removed or resized. Drag it up or down and a little sideways; the lower half of the screen is where it can go."
            color: root.mt.pInkSub
            font.family: root.mt.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MiniKey {
            icon: "align_horizontal_center"
            onActivated: LockEditService.apply(LM.setCore(LockEditService.board, LM.coreLimits().x, LM.coreLimits().y))
        }
    }

    // ===== a widget =====
    Column {
        id: col
        visible: root.info !== null
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        spacing: 6

        // Its name, and the remove key.
        Item {
            width: col.width
            height: 32

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.info ? root.info.icon : ""
                    size: 20
                    weight: 600
                    color: root.mt.pInk
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.info ? root.info.title.toUpperCase() : ""
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                    font.styleName: root.mt.fontStyleBold
                }
            }

            MiniKey {
                anchors.right: parent.right
                icon: "delete"
                onActivated: LockEditService.remove(root.uid)
            }
        }

        // Size.
        Row2 {
            width: col.width
            title: "SIZE"

            Row {
                spacing: 8

                MiniKey {
                    icon: "remove"
                    onActivated: LockEditService.stepScale(root.uid, -1, 0.1)
                }

                Text {
                    width: 52
                    height: 32
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.spec ? EM.percent(root.spec.scale) : ""
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                    font.styleName: root.mt.fontStyleBold
                }

                MiniKey {
                    icon: "add"
                    onActivated: LockEditService.stepScale(root.uid, 1, 0.1)
                }

                MiniKey {
                    label: "100%"
                    dim: root.spec !== null && root.spec.scale === 1
                    onActivated: LockEditService.setScale(root.uid, 1)
                }
            }
        }

        // One row per option.
        Repeater {
            model: root.info ? root.info.options : []

            Row2 {
                id: opt

                required property var modelData

                readonly property var value: root.spec ? root.spec.options[opt.modelData.key] : undefined

                width: col.width
                title: EM.optionLabel(opt.modelData.key).toUpperCase()

                // A list of choices, or ON / OFF.
                SegmentSwitch {
                    visible: opt.modelData.type === "enum" || opt.modelData.type === "bool"
                    width: Math.min(parent.width, (opt.modelData.type === "bool" ? 2 : opt.modelData.values.length) * 74 + 6)
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    options: opt.modelData.type === "bool"
                        ? [{ id: "true", label: "On" }, { id: "false", label: "Off" }]
                        : opt.modelData.values.map(v => ({ id: v, label: EM.valueLabel(v) }))
                    current: String(opt.value)
                    onPicked: id => LockEditService.setOption(root.uid, opt.modelData.key,
                        opt.modelData.type === "bool" ? id === "true" : id)
                }

                // Words.
                Item {
                    visible: opt.modelData.type === "string"
                    anchors.fill: parent

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: root.mt.pSurfaceHover
                        border.width: words.activeFocus ? 2 : 1
                        border.color: words.activeFocus ? root.mt.accentMint : root.mt.pLine
                    }

                    TextInput {
                        id: words
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        maximumLength: opt.modelData.max > 0 ? opt.modelData.max : 120
                        selectByMouse: true
                        onActiveFocusChanged: root.typing = words.activeFocus
                        color: root.mt.pInk
                        selectionColor: root.mt.accentMint
                        selectedTextColor: root.mt.colBorder
                        font.family: root.mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        // What the board says; typing is only saved when you press Enter or
                        // click away, so one edit is one undo.
                        text: opt.modelData.type === "string" && opt.value !== undefined ? String(opt.value) : ""
                        onEditingFinished: {
                            if (opt.modelData.type === "string" && words.text !== String(opt.value))
                                LockEditService.setOption(root.uid, opt.modelData.key, words.text)
                        }
                    }
                }

                // A picture.
                Row {
                    visible: opt.modelData.type === "path"
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    MiniKey {
                        icon: "folder_open"
                        onActivated: LockEditService.pickPicture(root.uid)
                    }

                    Text {
                        width: opt.width - 92 - 40 - 8 - 48
                        height: 32
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        text: opt.value ? String(opt.value).split("/").pop() : "No picture yet"
                        color: opt.value ? root.mt.pInk : root.mt.pInkSub
                        font.family: root.mt.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MiniKey {
                        icon: "close"
                        dim: !opt.value
                        onActivated: LockEditService.setOption(root.uid, opt.modelData.key, "")
                    }
                }
            }
        }
    }
}
