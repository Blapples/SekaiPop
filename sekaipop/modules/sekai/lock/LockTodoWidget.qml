import QtQuick
import qs.services
import qs.modules.common

// Your to-do list (the desktop To-Do widget's, services/TodoService.qml). A to-do list is
// private, so by default only a COUNT is shown ("3 tasks left"); nothing you wrote is on the
// screen anybody can see. Option `details`: show the next task's words as well. Nothing is
// drawn when the list is empty. Read-only: it never ticks, adds or removes a task.
LockWidget {
    id: root

    readonly property bool details: root.opt("details", false) === true
    readonly property bool has: TodoService.total > 0
    readonly property bool shown: root.has || root.preview
    readonly property int open: root.has ? TodoService.total - TodoService.doneCount : 3

    // The first task that is not ticked off (read again when the counts change).
    readonly property string nextTitle: {
        if (!root.has)
            return "Water the plants"
        const counted = TodoService.total + TodoService.doneCount
        const list = TodoService.items
        for (let i = 0; counted >= 0 && i < list.count; i++) {
            const t = list.get(i)
            if (!t.done)
                return String(t.title)
        }
        return ""
    }

    readonly property string countText: root.open + (root.open === 1 ? " task left" : " tasks left")
    readonly property bool allDone: root.has && root.open === 0

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockInfoCapsule {
        id: cap
        visible: root.shown
        px: root.px
        capH: root.capH
        capPad: root.capPad
        icon: root.allDone ? "task_alt" : "checklist"
        iconColor: root.allDone ? LockPalette.mint : LockPalette.lavenderText
        title: root.allDone ? "All done" : (root.details && root.nextTitle !== "" ? root.nextTitle : root.countText)
        subtitle: !root.allDone && root.details && root.nextTitle !== "" ? root.countText : ""
    }
}
