import QtQuick
import qs.services
import qs.modules.common

// How many notifications are waiting. Only the number: what a message says, who it is from and
// which app sent it are never on the lockscreen. Nothing is drawn when there are none. The
// number comes from services/NotificationCount.qml, which the shell keeps up to date from the
// notification daemon; this widget never reads, opens or dismisses a notification.
LockWidget {
    id: root

    readonly property int count: root.preview && NotificationCount.count === 0 ? 3 : NotificationCount.count
    readonly property bool shown: root.count > 0

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockInfoCapsule {
        id: cap
        visible: root.shown
        px: root.px
        capH: root.capH
        capPad: root.capPad
        icon: "notifications"
        iconColor: LockPalette.mint
        title: root.count + (root.count === 1 ? " notification" : " notifications")
    }
}
