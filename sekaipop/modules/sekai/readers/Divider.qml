import QtQuick
import qs.modules.sekai.readers

// Separator line: the shell's divider grey, two pixels like the lines between its blocks.
//
// Both `height` and `implicitHeight` are 2, so it also keeps its line inside a Layout.
Rectangle {
    implicitHeight: 2
    height: 2
    color: Colors.outline_variant
}
