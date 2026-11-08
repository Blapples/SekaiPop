pragma Singleton
import QtQuick
import Quickshell

// The last weather reading, kept for the whole life of the shell.
//
// Why it exists: every WeatherSource.qml asks Open-Meteo for itself, and some of the things
// that own one are built and destroyed all the time. The desktop weather card is unloaded
// while the screen is locked (shell.qml `widgetsAllowed`) and built again after the unlock,
// and the lockscreen's weather widget is built fresh at every lock. Each new one started with
// NO reading, so it drew nothing (or "--") until its own fetch came back, and if that fetch
// failed (the network is often not up for a second after waking) it stayed empty for
// 15 minutes.
//
// Now every successful fetch is stored here, and a new WeatherSource starts from it: the
// widget shows the last reading at once, and the source only asks again when that reading is
// older than 5 minutes.
//
// It holds the raw Open-Meteo answer (not the formatted texts), so a change of unit or clock
// format still redraws it. The reading belongs to one Location setting; another Location
// gets nothing from here.
Singleton {
    id: root

    property string location: ""
    property var place: null
    property double placeMs: 0
    property var data: null
    property double ms: 0
    property string updatedText: ""

    function store(location, place, placeMs, data, ms, updatedText) {
        root.location = location
        root.place = place
        root.placeMs = placeMs
        root.data = data
        root.ms = ms
        root.updatedText = updatedText
    }

    // The stored reading for this Location setting, or null.
    function get(location) {
        if (!root.data || root.ms <= 0 || root.location !== location)
            return null
        return {
            place: root.place,
            placeMs: root.placeMs,
            data: root.data,
            ms: root.ms,
            updatedText: root.updatedText
        }
    }
}
