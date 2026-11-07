pragma Singleton
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import Quickshell

// Shared XMLHttpRequest helpers for the backend-backed services (Manga, Anime,
// Novel), which each carried a byte-identical private copy of these.
//
// Every call builds its own request object, so nothing is shared between callers.
Singleton {
    // onDone(err, body, raw) — err is null on success, "HTTP <status>" otherwise; `raw` is the
    // reply text either way (a backend explains a refusal in it: {"error": "..."}).
    function get(url, onDone) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) onDone(null, xhr.responseText, xhr.responseText)
            else onDone("HTTP " + xhr.status, null, xhr.responseText)
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function post(url, data, onDone) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) onDone(null, xhr.responseText, xhr.responseText)
            else onDone("HTTP " + xhr.status, null, xhr.responseText)
        }
        xhr.open("POST", url)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(data))
    }
}
