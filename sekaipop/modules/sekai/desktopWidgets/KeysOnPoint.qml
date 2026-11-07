import QtQuick

// When a desktop widget's window may ask for the keyboard: only while the pointer is
// on it (so the click that starts typing finds it OnDemand), or while it already has
// the keyboard (typing goes on after the pointer has left). The rest of the time its
// keyboard interactivity is None.
//
// Why: Hyprland hands the keyboard to an OnDemand layer as it is mapped. Desktop Focus
// Mode maps the widgets again, one after another, whenever an empty workspace comes up,
// so every widget that was always OnDemand took the keyboard as it popped in, and a
// launcher opened right after (Rofi) could not be typed into for about a second
// (issue #72). A window that maps as None and only turns OnDemand under the pointer
// never takes it uninvited.
//
// Put one anywhere in the window and use `wanted`:
//
//   WlrLayershell.keyboardFocus: keys.wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
//   KeysOnPoint { id: keys }
//
// It is NOT an overlay. The first version was a full-window Item with a HoverHandler put
// last (on top), and a HoverHandler on top takes the hover from everything under it, with
// `blocking: false` too (Qt 6.12 tested): no task row, button or tile on the card ever saw
// the mouse, so the To-Do's trash / pencil / grip (they show on hover) and the other hover
// looks were gone. This one is a size-less Item whose HoverHandler is attached to the
// window's content item (`parent: root.parent`): the items inside get the hover first, as
// they should, and this still hears it as long as the handlers inside are non-blocking
// (`blocking: false`, as the To-Do row and EditChrome's now are; a MouseArea is fine).
Item {
    id: root

    readonly property bool wanted: hover.hovered || root.Window.active

    width: 0
    height: 0

    HoverHandler {
        id: hover
        parent: root.parent
        blocking: false
    }
}
