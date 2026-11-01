// Smart hide's geometry feed (DockService.hold) must stay on while any dock in Smart hide
// exists. At startup the shell builds the dock twice on one monitor; with a key per monitor
// the second dock's claim was skipped (the key was held) and the first released it on its
// way out, so the window list was never read again and the dock stood over a maximized
// window (issue #116). The wiring is read from source; `hold` and `newHoldKey` run against a
// fake service. Run: node smart_hide_hold_test.js
const fs = require('fs'), assert = require('assert')
const D = fs.readFileSync(__dirname + '/../../modules/sekai/dock/Dock.qml', 'utf8')
const S = fs.readFileSync(__dirname + '/../../services/DockService.qml', 'utf8')

assert.ok(/property string holdKey: ""/.test(D), 'the key is not a binding on the monitor')
assert.ok(!/holdKey: "dock-" \+/.test(D), 'no key per monitor')
assert.ok(/dockWindow\.holdKey = DockService\.newHoldKey\("dock"\)\s+DockService\.hold\(dockWindow\.holdKey, dockWindow\.smartOn\)/.test(D),
          'each dock takes its own key when it is built, then holds')
assert.ok(/Component\.onDestruction: \{\s+DockService\.hold\(dockWindow\.holdKey, false\)/.test(D), 'and lets go of it on its way out')

const fn = name => {
    const i = S.indexOf('    function ' + name + '(')
    assert.ok(i > 0, name)
    return S.slice(i, S.indexOf('\n    }\n', i) + 6).replace(/^\s*function \w+\(([^)]*)\)/, 'function ($1)')
}
const root = { holders: {}, keysGiven: 0 }
Object.defineProperty(root, 'wanted', { get() { return Object.keys(this.holders).length > 0 } })
const hold = new Function('root', 'return (' + fn('hold') + ')')(root)
const newHoldKey = new Function('root', 'return (' + fn('newHoldKey') + ')')(root)

// Startup as it happens on one monitor: dock A built and holding, dock B built and holding,
// A destroyed.
const a = newHoldKey('dock'), b = newHoldKey('dock')
assert.notStrictEqual(a, b, 'two docks never share a key')
hold(a, true)
hold(b, true)
hold(a, false)
assert.ok(root.wanted, 'the feed stays on for the dock that is left')
hold(b, false)
assert.ok(!root.wanted, 'and goes off when the last one lets go')
// A dock that only learns its key when it is completed: an early smartOn change holds nothing.
hold('', true)
assert.ok(!root.wanted, 'an empty key holds nothing')
console.log('smart_hide_hold_test: all checks passed')
