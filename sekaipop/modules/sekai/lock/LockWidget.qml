import QtQuick

// The base of every widget on the Custom lockscreen (LockCanvas.qml). A widget is a plain
// Item: the lock surface can not host a window or a popup, so everything is drawn inside it.
// The canvas hands each one the same few things and nothing else:
//
//   options   this widget's options (LockCanvasModel.js has already checked every one)
//   u         the screen's scale (1 at 1080 p tall), so px(n) is n design pixels
//   now       the time, which the canvas keeps current
//   media     the lockscreen's MediaSource (what is playing) | battery   its BatterySource
//   context   the shared LockContext (only for what a widget may need to hear, like a
//             resume from sleep); a widget never types into it
//   preview   true when drawn by the editor: show something even if there is nothing to show
//
// Rules a lock widget keeps (docs/LOCKCANVAS.md):
//   - It never takes the keyboard: the canvas catches every key for the password. No text
//     fields, no focus.
//   - It does nothing but draw, apart from the few safe actions a widget may offer (the
//     media keys). It never starts a program, opens a link or reaches into the session.
//   - It reads what it shows from the sources it is given or from its own passive source,
//     and costs nothing while nothing is locked (the canvas is only built while locking).
Item {
    id: root

    property var options: ({})
    property real u: 1
    property date now: new Date()
    property var media: null
    property var battery: null
    property var context: null
    property bool preview: false

    function px(n) {
        return Math.round(n * root.u)
    }

    // The small capsules (user, date, weather, battery, now playing) are all this tall and
    // pad their ends the same, so side by side they read as one family. The User widget's
    // avatar sets the height; the others follow it.
    readonly property real capH: root.px(116)
    readonly property real capPad: root.px(44)

    // One option, or `fallback` if it is not there.
    function opt(key, fallback) {
        const v = root.options ? root.options[key] : undefined
        return v === undefined ? fallback : v
    }
}
