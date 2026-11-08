pragma Singleton
import QtQuick
import Quickshell

// How many notifications are in the history, kept where the lockscreen can reach it.
//
// The notification daemon (NotificationSource.qml) is one object built in shell.qml, and the
// lockscreen's widgets can not reach it from where they live. shell.qml binds `count` to the
// daemon's own count (a Binding next to it), and the Notifications lockscreen widget
// (LockNotificationsWidget.qml) reads this. Only the NUMBER is kept here on purpose: nothing
// a notification says (its title, its text, the app) goes anywhere near the lockscreen.
Singleton {
    property int count: 0
}
