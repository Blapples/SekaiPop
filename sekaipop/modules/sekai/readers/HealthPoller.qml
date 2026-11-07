// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick

// Polls `<url>/health` until the backend answers, then stops and emits ready()
// exactly once. The caller keeps its own start-up work in onReady so the order
// of its logging and follow-up fetches is unchanged.
Timer {
    id: root

    property string url: ""
    signal ready

    interval: 150
    repeat: true
    running: true

    onTriggered: {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                root.stop()
                root.ready()
            }
        }
        xhr.open("GET", root.url + "/health")
        xhr.send()
    }
}
