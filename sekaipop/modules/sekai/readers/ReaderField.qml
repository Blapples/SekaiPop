import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// A one-line text field in the shell's own build (the search pill's: white pill, outline, hard
// shadow, a cyan ring while it has the keyboard), without the magnifier. For a client ID, a
// pasted token. `secret` hides what is typed; Enter reports accepted().
//
//   ReaderField { placeholder: "Client ID"; onAccepted: save(text) }
Item {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property bool secret: false
    property bool readOnly: false
    readonly property bool focused: input.activeFocus

    signal accepted()

    function clear() { input.text = "" }

    implicitWidth: 240
    implicitHeight: 40

    Rectangle {
        x: Theme.shadowOffset - 1
        y: Theme.shadowOffset - 1
        width: root.width
        height: root.height
        radius: height / 2
        color: Colors.lineShadow
        antialiasing: true
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Colors.line
        antialiasing: true

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Colors.primary
            visible: input.activeFocus && !root.readOnly
            antialiasing: true
        }

        Text {
            visible: input.text.length === 0
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            elide: Text.ElideRight
            text: root.placeholder
            color: Colors.on_surface_variant
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        TextInput {
            id: input
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            clip: true
            selectByMouse: true
            readOnly: root.readOnly
            echoMode: root.secret ? TextInput.Password : TextInput.Normal
            color: Colors.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 13
            Keys.onReturnPressed: root.accepted()
            Keys.onEnterPressed: root.accepted()
        }
    }
}
