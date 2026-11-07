pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// The readers' one scale: sizes, weights and heights that every panel draws from, so a new
// screen picks from a short list instead of inventing a number.
//
//   Type    11 caption (stamps, chips, labels, dates)  13 body (rows, titles)  16 screen title
//           30 wordmark. Nothing below 11.
//   Weight  800 for stamps, chips and the wordmark only; 700 for titles; 500 for everything
//           that is only read (meta, dates, table cells). Hierarchy comes from the weight as
//           well as the size, so a table does not shout like its titles do.
//   Height  24 stamp  .  32 chip  .  40 field and key  (rows are 48, plates are taller).
//   Colour  Solid accent = a selection or the one primary action of a screen (the lit tab or
//           chip, Continue, the score stamp). Everything else that is information (status,
//           year, tracked, last read) is tonal: dark fill, ink text, accent only on the line.
//
// The named styles fall back to the weight when the font has no instance of that name
// (see ThemeSet.fontStyleBold), so nothing breaks on a system without them.
Singleton {
    readonly property int sizeCaption: 11
    readonly property int sizeBody: 13
    readonly property int sizeTitle: 16

    readonly property int weightStrong: Font.ExtraBold
    readonly property string styleStrong: Theme.fontStyleBold
    readonly property int weightTitle: Font.Bold
    readonly property string styleTitle: "Bold"
    readonly property int weightBody: Font.Medium
    readonly property string styleBody: "Medium"

    readonly property int hBadge: 24
    readonly property int hChip: 32
    readonly property int hField: 40
    readonly property int hRow: 48

    readonly property int gutter: 16

    // The dark, see-through plate a type tag wears on a cover, so it does not cover the art
    // and reads in every mode (the text on it is fixed light).
    readonly property color tagFill: Qt.rgba(0.11, 0.08, 0.16, 0.78)
    readonly property color tagInk: "#f2eef7"
}
