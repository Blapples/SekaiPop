import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// Gets the next chapter ready while the current one is still being read: its page list is
// asked from the server, and the first few pages are downloaded and held, so when the reader
// moves on the chapter is there at once instead of after "loading pages".
//
//   preload.start(chapterId)      ask for a chapter (does nothing if it is already the one)
//   preload.take(chapterId)       its pages as the reader keeps them, or null if not (yet) there
//   preload.reset()               let it go
//
// The page list comes from the same /pages route Manga.fetchChapterPages uses, so a source
// that serves its pages another way (a provider behind the server) is no different here.
Item {
    id: root

    property string chapterId: ""
    property var pages: []
    property bool ready: false
    property bool failed: false
    // How many of the first pages are downloaded ahead.
    property int imageCount: 8

    property int _req: 0

    function reset() {
        root._req++
        root.chapterId = ""
        root.pages = []
        root.ready = false
        root.failed = false
    }

    function start(id) {
        if (!id || id.length === 0 || root.chapterId === id)
            return
        root.reset()
        root.chapterId = id
        const rid = root._req
        Http.get(Manga.apiUrl + "/pages?chapterId=" + encodeURIComponent(id), function (err, body) {
            if (rid !== root._req)
                return
            if (err) {
                root.failed = true
                return
            }
            try {
                const data = JSON.parse(body)
                if (!Array.isArray(data) || data.length === 0) {
                    root.failed = true
                    return
                }
                root.pages = data.map((p, idx) => ({ index: idx, url: p.img || "", localPath: p.img || "", ready: true }))
                root.ready = true
            } catch (e) {
                root.failed = true
            }
        })
    }

    function take(id) {
        return root.ready && root.chapterId === id ? root.pages : null
    }

    // The first pages, kept loading (and so in the image cache) until the chapter is taken.
    Repeater {
        model: root.ready ? Math.min(root.imageCount, root.pages.length) : 0

        delegate: Image {
            required property int index

            visible: false
            width: 1
            height: 1
            asynchronous: true
            cache: true
            source: root.pages[index] ? root.pages[index].url : ""
        }
    }
}
