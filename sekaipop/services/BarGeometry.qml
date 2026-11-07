pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// Where the bar really ends, for whatever sits beside it (the manga / novel reader panels).
//
// The bar reserves a strip on its edge (Bar.qml: exclusiveZone), and every layer window left at
// ExclusionMode.Normal starts where that strip ends. But the strip is NOT the same as what is
// drawn, and the difference changes with the bar style:
//
//   float        drawn 1 px off the edge, body 72 / 61 thick -> ends 1 px inside the strip
//   straight     drawn flush, 72 / 61 thick                   -> ends 1-2 px inside the strip
//   transparent  only the pills (52 wide / pill tall), centred in the body; the strip is then
//                trimmed by gaps_out + 5 (made for the TILED windows, Hyprland adds gaps_out
//                on top of the zone, layer windows get no such gap) -> the strip ends INSIDE
//                the pills
//   capsule      drawn 8 px off the edge, 56 / 39 thick; the strip is trimmed by gaps_out
//                -> ends inside the capsule once gaps_out is more than 8
//
// So a window that simply starts at the zone's edge touches the bar in Float / Straight and
// overlaps it in Transparent / Capsule. The reader's panel, which is clipped by its
// window's edge, showed that as a card that sat next to the bar in one style and on top of it in
// another. `shiftReal()` is how far that window's edge has to move (a layer-shell margin) to
// start the same `gap` past the drawn bar in every style.
//
// The formulas for the zone mirror Bar.qml (stripSize, transparentTrim, exclusiveZone). If those
// change, change them here too.
Singleton {
    id: root

    readonly property int style: BarStyleService.index
    readonly property string position: BarPositionService.position
    readonly property bool vertical: BarPositionService.vertical
    readonly property bool autoHide: SettingsService.get("bar.hideMode") === "auto"

    // Design pixels between the bar's drawn edge and the edge of the window beside it.
    // (Float and Straight already had 1-2 px there; the cards keep their own 12 px margin on top.)
    readonly property real gap: 2

    // Bar.qml's `transparentExtraGap`.
    readonly property real transparentExtraGap: 5

    // What the bar asks for along its thickness, design px (Bar.qml stripSize before scaling).
    function stripDesign(mt) {
        if (root.style === 3)
            return root.vertical ? mt.capStripV : mt.capStrip
        return BarPositionService.thicknessFor(root.position)
    }

    // What the bar reserves, REAL px (Bar.qml: stripSize - transparentTrim; nothing while the
    // bar hides itself).
    function reservedReal(screen) {
        if (root.autoHide)
            return 0
        const mt = Theme.of(screen)
        const k = ShellScale.forScreen(screen)
        const strip = Math.round(root.stripDesign(mt) * k)
        const gapsOut = Math.max(0, HyprlandSettings.num("general.gaps_out"))
        let trim = 0
        if (root.style === 2)
            trim = Math.min(gapsOut + Math.round(root.transparentExtraGap * k), Math.round(strip * 0.6))
        else if (root.style === 3)
            trim = Math.min(gapsOut, Math.round(strip * 0.6))
        return strip - trim
    }

    // From the bar's own screen edge to the last pixel it draws on the inside, design px.
    function visibleDesign(mt) {
        const v = root.vertical
        switch (root.style) {
        case 0: // float: 1 px off the edge, then the body (Bar.qml edgeGap / Status_Bar size)
            return 1 + (v ? mt.barVBody : 61)
        case 1: // straight: flush with the edge
            return v ? mt.barVBody : 61
        case 2: // transparent: just the pills, centred in the body that starts 1 px in
            return v ? 1 + (mt.barVBody + mt.barVPillWidth) / 2
                     : 1 + (61 + mt.pillHeight + mt.shadowOffset) / 2
        default: // capsule: capEdgeGap off the edge, then the face (the flat one with its shadow)
            return mt.capEdgeGap + (v ? mt.capVBarFace : mt.capBarHeight)
        }
    }

    // How far the edge of a window that starts at the end of the bar's strip has to move to sit
    // `gap` past what is drawn, REAL px. Positive = further from the bar's screen edge,
    // negative = closer to it (a layer-shell margin can be negative). 0 while the bar hides
    // itself: the strip is empty and the bar slides in over whatever is there.
    function shiftReal(screen) {
        if (root.autoHide)
            return 0
        const mt = Theme.of(screen)
        const k = ShellScale.forScreen(screen)
        const line = Math.round((root.visibleDesign(mt) + root.gap) * k)
        return line - root.reservedReal(screen)
    }
}
