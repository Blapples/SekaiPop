import QtQuick
import qs.services
import qs.modules.common
import "../../common/functions/EventMath.js" as EM

// Your next event or deadline (the desktop Calendar card's, services/CalendarCardService.qml).
// Events are private, so by default only a COUNT is shown ("2 events today", or "Next: in 3
// days" when today is empty); titles and times stay off the screen. Option `details`: show the
// next entry's title and when it is. Nothing is drawn when there is nothing coming up.
// Read-only: it never adds, ticks off or changes an entry.
LockWidget {
    id: root

    readonly property bool details: root.opt("details", false) === true
    readonly property bool use24h: SettingsService.flag("time.use24h")

    // The next entry: an open deadline that is already late comes first, then today on.
    readonly property var next: {
        const list = EM.upcoming(CalendarCardService.events, root.now, 1)
        return list.length > 0 ? list[0] : null
    }
    readonly property int diff: root.next ? EM.diffTo(root.now, root.next.date) : 0

    readonly property int todayCount: {
        const key = EM.keyOf(root.now)
        let n = 0
        for (const e of CalendarCardService.events) {
            if (e.date === key && !(e.kind === "deadline" && e.done))
                n++
        }
        return n
    }

    readonly property bool has: root.next !== null
    readonly property bool shown: root.has || root.preview
    readonly property bool late: root.has && root.diff < 0

    readonly property string title: {
        if (!root.has)
            return root.details ? "Band rehearsal" : "2 events today"
        if (root.details)
            return String(root.next.title)
        if (root.todayCount > 0)
            return root.todayCount + (root.todayCount === 1 ? " event today" : " events today")
        return "Next: " + EM.countdown(root.next, root.diff)
    }

    readonly property string subtitle: {
        if (!root.details)
            return ""
        if (!root.has)
            return "Today \u00b7 " + EM.timeText("18:30", root.use24h)
        const when = EM.countdown(root.next, root.diff)
        return root.next.time ? when + " \u00b7 " + EM.timeText(root.next.time, root.use24h) : when
    }

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockInfoCapsule {
        id: cap
        visible: root.shown
        px: root.px
        capH: root.capH
        capPad: root.capPad
        icon: "event"
        iconColor: root.late ? LockPalette.pink : LockPalette.lavenderText
        title: root.title
        subtitle: root.subtitle
    }
}
