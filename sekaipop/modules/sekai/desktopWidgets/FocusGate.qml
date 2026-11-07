import QtQuick
import qs.services
import "../../common/functions/FocusMath.js" as FM

// One desktop widget's view of Desktop Focus Mode (services/FocusService.qml).
// Drop one into a widget's window and read it; the widget does not track
// windows or workspaces itself:
//
//   FocusGate {
//       id: gate
//       widgetId: "clock"
//       screenName: win.screen ? win.screen.name : ""
//   }
//
//   readonly property bool want: win.switchedOn && gate.show
//
// It answers four different questions, which are NOT the same thing (do not
// treat one as another: `visible: false` on a window stops none of the widget's
// timers, clocks or processes):
//
//   hidden      the monitor's workspace has something on it that hides the
//               desktop (the decision; instant)
//   show        the widget may be on screen and draw: not hidden, and it has
//               had its turn to wake up (the staggered return, below)
//   suspended   its non-essential work may be paused: it is not shown, and
//               "Suspend hidden widget workloads" is on. With that switched off
//               a hidden widget keeps its clock, fetches and audio running.
//   dimmed      not shown (for work that only slows down instead of stopping)
//   gone        (only for a gate with `unloads: true`, the ones shell.qml puts next to
//               each widget's LazyLoader) the widget has been hidden for UNLOAD_MS and
//               "Unload hidden widgets" is on: the loader destroys the widget. It is
//               cleared on this widget's turn to come back, so the rebuilds of five
//               widgets are staggered too. The visualizer is never unloaded while it
//               may keep listening in the background (its audio tap lives in it).
//
// Going away is immediate. Coming back is one widget after another
// (FocusMath.slotDelay: clock, user card, weather, to-do, visualizer, 70 ms
// apart) so five widgets do not start their clocks, fetches and first frames in
// the same frame. Not staggered: at start, and when Focus Mode is switched off.
QtObject {
    id: gate

    property string screenName: ""
    // clock | usercard | weathercard | todo | visualizer | image | notes | calendarcard | palettecard | lyrics | watertank | downloader (the wake-up
    // order; every Custom Image uses "image"; a desktop widget plugin is "plugin:<id>", last)
    property string widgetId: ""
    // Only the gates beside the LazyLoaders in shell.qml unload anything.
    property bool unloads: false
    // Long enough that going back and forth between an app and an empty workspace
    // does not destroy and rebuild a widget each time, and for the swallow to finish.
    readonly property int unloadMs: 2000

    property bool gone: false
    readonly property bool canUnload: gate.unloads && FocusService.unloadHidden
        && !(gate.widgetId === "visualizer" && FocusService.visualizerKeepsListening)

    readonly property bool hidden: FocusService.hiddenOn(gate.screenName)

    // False from the moment the widget is hidden until its turn to come back.
    property bool released: true

    readonly property bool show: !gate.hidden && gate.released
    readonly property bool dimmed: !gate.show
    readonly property bool suspended: !gate.show && FocusService.suspendWorkloads

    onHiddenChanged: {
        if (gate.hidden) {
            wake.stop()
            gate.released = false
            if (gate.canUnload)
                unloadTimer.restart()
        } else {
            unloadTimer.stop()
            if (!FocusService.enabled || wake.interval <= 0) {
                gate.released = true
                gate.gone = false
            } else {
                wake.restart()
            }
        }
    }

    onCanUnloadChanged: {
        if (!gate.canUnload) {
            unloadTimer.stop()
            gate.gone = false
        } else if (gate.hidden) {
            unloadTimer.restart()
        }
    }

    property Timer unloadTimer: Timer {
        interval: gate.unloadMs
        onTriggered: {
            if (gate.hidden && gate.canUnload)
                gate.gone = true
        }
    }

    // A widget that is created while the monitor is hidden starts hidden.
    Component.onCompleted: {
        gate.released = !gate.hidden
        if (gate.hidden && gate.canUnload)
            unloadTimer.restart()
    }

    property Timer wake: Timer {
        interval: FM.slotDelay(gate.widgetId)
        onTriggered: {
            gate.released = true
            gate.gone = false
        }
    }
}
