// The same list as manga/FilterMenu.qml, kept as its own copy because each reader's views are one folder.
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The list a Browse filter drops down under its key: a card with one row per option, a tick
// on the ones that are on, an optional search box over it (the tags have hundreds), and a
// small grey hint at the right of a row (a tag's category). It only reports a tap (picked);
// the caller decides whether that switches a value on and off or picks one and closes.
//
// `options` is a list of { label, value, hint }; `selected` the values that are on.
//
//   FilterMenu { options: [...]; selected: Novel.discoverGenres
//                onPicked: function(value) { Novel.toggleDiscoverGenre(value) } }
Column {
    id: root

    property var options: []
    property var selected: []
    property bool searchable: false
    property string placeholder: "Search…"
    property string emptyText: "Nothing here"
    // The most the list grows to before it scrolls
    property int maxListHeight: 220

    signal picked(var value)

    spacing: 6
    topPadding: 2
    bottomPadding: 6

    readonly property string query: searchable ? search.text.trim().toLowerCase() : ""

    readonly property var shown: {
        const all = options || []
        if (query.length === 0) return all
        return all.filter(function(o) { return o.label.toLowerCase().indexOf(query) >= 0 })
    }

    SearchPill {
        id: search
        visible: root.searchable
        width: parent.width - 6
        height: 36
        placeholder: root.placeholder
    }

    Rectangle {
        width: parent.width - 6
        height: Math.min(list.contentHeight, root.maxListHeight) + 12
        radius: 12
        color: Theme.surfaceHover
        border.width: 2
        border.color: Theme.colBorder
        antialiasing: true

        ListView {
            id: list
            anchors { fill: parent; margins: 6 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.shown

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: Item {
                id: row
                width: list.width
                height: 32

                readonly property bool on: root.selected.indexOf(modelData.value) >= 0

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: rowArea.containsMouse ? Theme.surfaceTint : "transparent"
                }

                MaterialIcon {
                    id: tick
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    name: "check"
                    size: 15
                    weight: 600
                    color: Theme.ink
                    opacity: row.on ? 1 : 0
                }

                Text {
                    anchors {
                        left: tick.right; leftMargin: 8
                        right: hint.left; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.label
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: row.on ? Font.ExtraBold : Font.Bold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    id: hint
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: modelData.hint || ""
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(modelData.value)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.shown.length === 0
            text: root.emptyText
            color: Theme.inkSub
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Bold
            font.styleName: Theme.fontStyleBold
        }
    }
}
