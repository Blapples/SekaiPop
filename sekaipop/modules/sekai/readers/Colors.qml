pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// The readers were written against Material 3 colour roles (Colors.primary, Colors.surface_container,
// ...). Here those roles are worked out from SekaiPop's own theme, so the panels follow the
// palette, the mode (light / dark / darker) and matugen like the rest of the shell.
// Uses the shell's one Theme, not a monitor's own (the panels are not tied to a screen).
Singleton {
    readonly property color ink: Theme.ink

    function withAlpha(c, a) {
        const k = Qt.color(c)
        return Qt.rgba(k.r, k.g, k.b, a)
    }

    // A step of the surface towards the ink: the "container" levels of M3.
    function _lift(a) {
        return Qt.tint(Theme.surface, Qt.rgba(ink.r, ink.g, ink.b, a))
    }

    // The panel's frame is the shell's flat card (Theme.surface); what sits inside it, the
    // grids and lists, lies on the launcher's warm paper, so the white cards stand off it.
    readonly property color frame: Theme.surface
    readonly property color background: Theme.paper
    readonly property color surface_container_low: Theme.surface
    readonly property color surface_container: _lift(0.06)
    readonly property color surface_container_high: _lift(0.10)
    readonly property color surface_container_highest: _lift(0.15)

    readonly property color on_surface: Theme.ink
    readonly property color on_surface_variant: Theme.inkSub
    readonly property color outline: Qt.rgba(ink.r, ink.g, ink.b, 0.5)
    readonly property color outline_variant: Theme.surfaceDivider

    readonly property color primary: Theme.accentCyan
    readonly property color on_primary: Theme.colBorder
    readonly property color primary_container: Qt.tint(Theme.surface, Qt.rgba(primary.r, primary.g, primary.b, 0.24))
    readonly property color on_primary_container: Theme.ink
    readonly property color primary_fixed_dim: Qt.darker(primary, 1.2)
    readonly property color tertiary: Theme.accentMint
    // What a chapter is read on: the palette's own dark tone, a step darker, so the pages
    // and the type stand out of it in every mode.
    readonly property color stage: Qt.darker(Theme.colDeep, 1.5)
    readonly property color page: Qt.darker(Theme.colDeep, 1.25)
    // The look of the shell's own blocks: outline, hard shadow, accent pair.
    readonly property color line: Theme.line
    readonly property color lineShadow: Theme.lineShadow
    readonly property color accentA: Theme.accentMint
    readonly property color accentB: Theme.accentCyan
    readonly property color ink_on_accent: Theme.colBorder
    readonly property color error: "#e5566d"
}
