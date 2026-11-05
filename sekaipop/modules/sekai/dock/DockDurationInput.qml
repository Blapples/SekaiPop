import QtQuick

Rectangle {
    id: field
    required property var theme
    property alias text: editor.text
    property int maximum: 59
    readonly property bool acceptableInput: editor.acceptableInput
    signal accepted()

    width: 48
    height: 30
    radius: 9
    color: field.theme.surface
    border.width: 2
    border.color: editor.activeFocus ? field.theme.accentCyan : field.theme.line

    TextInput {
        id: editor
        anchors.fill: parent
        anchors.margins: 5
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        activeFocusOnTab: true
        clip: true
        maximumLength: String(field.maximum).length
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: field.maximum; locale: "C" }
        color: field.theme.ink
        selectionColor: field.theme.accentCyan
        selectedTextColor: field.theme.colBorder
        font.family: field.theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.Bold
        onActiveFocusChanged: if (activeFocus) selectAll()
        onAccepted: field.accepted()
    }
}
