import QtQuick
import qs.services
import qs.modules.common
import "../../common/functions/EventMath.js" as EM

// Days to (or since) a day you pick: a concert, a birthday, a deadline. Options: `label`
// (what it is, up to 40 characters) and `date` (YYYY-MM-DD; the editor's words box takes it).
// Nothing is drawn until the date is a real day. You can put up to four on the screen.
LockWidget {
    id: root

    readonly property string rawDate: String(root.opt("date", "")).trim()
    readonly property bool valid: EM.parseDate(root.rawDate) !== null
    readonly property bool shown: root.valid || root.preview
    readonly property int diff: root.valid ? EM.diffTo(root.now, root.rawDate) : 12
    readonly property int days: Math.abs(root.diff)
    readonly property string label: String(root.opt("label", "")).trim()

    readonly property string title: root.diff === 0 ? "Today" : root.days + (root.days === 1 ? " day" : " days")

    readonly property string subtitle: {
        if (!root.valid)
            return root.label !== "" ? root.label : "Set a date"
        if (root.diff === 0)
            return root.label
        const word = root.diff > 0 ? "until " : "since "
        return root.label !== "" ? word + root.label : (root.diff > 0 ? "to go" : "ago")
    }

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockInfoCapsule {
        id: cap
        visible: root.shown
        px: root.px
        capH: root.capH
        capPad: root.capPad
        icon: root.valid && root.diff === 0 ? "celebration" : "hourglass_top"
        iconColor: root.valid && root.diff === 0 ? LockPalette.mint : LockPalette.lavenderText
        title: root.title
        subtitle: root.subtitle
    }
}
