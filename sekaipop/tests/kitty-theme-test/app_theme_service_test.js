// Run with: node --test sekaipop/tests/kitty-theme-test/app_theme_service_test.js
// Execute the service's JavaScript and process callbacks with simulated process
// results. No desktop session or user configuration is read or changed.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const test = require("node:test")
const vm = require("node:vm")
const locate = require("../lib/locate.js")
const source = fs.readFileSync(process.env.APP_THEME_SERVICE_SOURCE || locate("services/AppThemeService.qml"), "utf8")

function service() {
    const root = { status: {}, failures: {}, queue: [], settled: true, script: "app-theme.sh" }
    const preferences = {}, writes = [], commands = []
    const runner = { running: false, exec(args) { this.running = true; commands.push(args) } }
    const statusProc = { running: false, pending: false, exec() { this.running = true } }
    const SettingsService = {
        flag(key) { return !!preferences[key] },
        set(key, value) { preferences[key] = value; writes.push([key, value]) }
    }
    const context = vm.createContext({ root, runner, statusProc, SettingsService })
    const descriptors = source.match(/readonly property var targets: (\[[\s\S]*?\n    \])/)[1]
    root.targets = vm.runInContext(descriptors, context)
    for (const m of source.matchAll(/^    function (\w+)\(([^\n]*)\) \{([\s\S]*?)\n    \}/gm))
        vm.runInContext(`root.${m[1]} = function(${m[2]}) {${m[3]}\n}`, context)
    root.colours = () => ["background=#123456"]
    const runBlock = source.slice(source.indexOf("id: runner"), source.indexOf("    function applyScripts"))
    const finish = vm.runInContext(runBlock.match(/onExited: (exitCode => \{[\s\S]*?\n        \})/)[1], context)
    const statusBlock = source.slice(source.indexOf("id: statusProc"), source.indexOf("    Component.onCompleted:"))
    const receive = vm.runInContext(`(text) => {${statusBlock.match(/onStreamFinished: \{([\s\S]*?)\n            \}/)[1]}\n}`, context)
    return {
        root, runner, statusProc, preferences, writes, commands,
        complete(action, script, code) {
            root.enqueue([action, script])
            runner.running = false
            finish(code)
        },
        status(values) {
            if (!statusProc.running) root.refreshStatus()
            receive(Object.entries(values).map(([key, value]) => `${key}=${value}`).join("\n"))
            statusProc.running = false
            if (statusProc.pending) {
                statusProc.pending = false
                root.refreshStatus()
            }
        }
    }
}

test("failed explicit enable survives an off/no-op sync and other targets' success", () => {
    const s = service()
    s.complete("apply", "kitty", 1)
    s.status({ kitty: "off" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.complete("apply", "fish", 0)
    s.status({ kitty: "off", fish: "on" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.complete("sync", "kitty", 0)
    s.status({ kitty: "off" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    assert.equal(s.root.enabled("kitty"), false)
})

test("failed background sync cannot replace an explicit operation failure", () => {
    for (const action of ["apply", "enable", "revert"]) {
        const s = service()
        s.complete(action, "kitty", 1)
        s.status({ kitty: "conflict" })
        const explicitFailure = s.root.failures.kitty
        s.complete("sync", "kitty", 1)
        assert.equal(s.root.failures.kitty, explicitFailure)
        assert.equal(s.root.failures.kitty.action, action)
        s.status({ kitty: "off" })
        assert.equal(s.root.stateOf("kitty"), "conflict")
        assert.equal(s.root.enabled("kitty"), false)
        s.complete("sync", "kitty", 0)
        s.status({ kitty: "off" })
        assert.equal(s.root.failures.kitty, explicitFailure)
    }
})

test("an ambiguous marker or failed enable does not imply an installed hook", () => {
    const s = service()
    s.status({ kitty: "conflict" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    assert.equal(s.root.enabled("kitty"), false)
    s.complete("apply", "kitty", 1)
    s.status({ kitty: "conflict" })
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "conflict" })
    assert.equal(s.root.enabled("kitty"), false)
    assert.equal(s.root.failures.kitty.action, "apply")
})

test("successful explicit retry or revert clears its failure", () => {
    for (const action of ["apply", "enable", "revert"]) {
        const s = service()
        s.complete("apply", "kitty", 1)
        s.status({ kitty: "off" })
        s.complete(action, "kitty", 0)
        s.status({ kitty: action === "revert" ? "off" : "on" })
        assert.equal(s.root.stateOf("kitty"), action === "revert" ? "off" : "applied")
    }
})

test("manual repair or disable clears a failed sync on a fresh status response", () => {
    for (const repaired of ["on", "off"]) {
        const s = service()
        s.complete("sync", "kitty", 1)
        s.status({ kitty: "blocked" })
        assert.equal(s.root.stateOf("kitty"), "conflict")
        s.status({ kitty: repaired })
        assert.equal(s.root.stateOf("kitty"), repaired === "on" ? "applied" : "off")
    }
})

test("a repaired blocked hook awaiting colours does not retain the previous sync error", () => {
    const s = service()
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "blocked" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.status({ kitty: "pending" })
    assert.equal(s.root.stateOf("kitty"), "pending")
})

test("an on status cannot dismiss a sync IO failure it has not diagnosed", () => {
    const s = service()
    s.status({ kitty: "on" })
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "on" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.status({ kitty: "on" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.complete("sync", "kitty", 0)
    s.status({ kitty: "on" })
    assert.equal(s.root.stateOf("kitty"), "applied")
})

test("a missing executable is not a successful retry", () => {
    const s = service()
    s.complete("apply", "kitty", 1)
    s.status({ kitty: "off" })
    s.complete("apply", "kitty", 3)
    s.status({ kitty: "off" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
})

test("status started before a new failure cannot discard that failure", () => {
    const s = service()
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "blocked" })
    s.root.refreshStatus()
    s.complete("sync", "kitty", 1)
    const newFailure = s.root.failures.kitty
    s.status({ kitty: "blocked" })
    assert.equal(s.root.failures.kitty, newFailure)
    s.status({ kitty: "blocked" })
    assert.equal(s.root.failures.kitty, undefined)
    s.status({ kitty: "pending" })
    assert.equal(s.root.stateOf("kitty"), "pending")
})

test("a verified but blocked hook keeps the switch enabled so it can be turned off", () => {
    const s = service()
    s.status({ kitty: "blocked" })
    assert.equal(s.root.enabled("kitty"), true)
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.root.setEnabled("kitty", false)
    assert.deepEqual(Array.from(s.commands[0]), ["sh", "app-theme.sh", "revert", "kitty"])
    assert.deepEqual(s.writes, [])
})

test("backend configuration errors need no duplicate sync failure record", () => {
    const s = service()
    s.status({ kitty: "blocked" })
    assert.equal(s.root.enabled("kitty"), true)
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "blocked" })
    assert.equal(s.root.failures.kitty, undefined)
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.status({ kitty: "on" })
    assert.equal(s.root.stateOf("kitty"), "applied")
    s.complete("enable", "kitty", 1)
    s.status({ kitty: "blocked" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    assert.equal(s.root.enabled("kitty"), true)
})

test("an installed hook awaiting colours is pending rather than applied", () => {
    const s = service()
    s.status({ kitty: "pending" })
    assert.equal(s.root.enabled("kitty"), true)
    assert.equal(s.root.stateOf("kitty"), "pending")
    s.complete("sync", "kitty", 1)
    s.status({ kitty: "pending" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    s.complete("sync", "kitty", 0)
    s.status({ kitty: "on" })
    assert.equal(s.root.stateOf("kitty"), "applied")
    s.complete("apply", "kitty", 1)
    s.status({ kitty: "pending" })
    assert.equal(s.root.stateOf("kitty"), "conflict")
    assert.equal(s.root.enabled("kitty"), true)
})

test("target descriptors drive enable, deferred enable, sync and revert", () => {
    const s = service()
    s.root.targets = [{ id: "other", scripts: ["other-script"], statusDriven: true, syncAction: "sync", enableAction: "enable" }]
    s.root.settled = false
    s.root.setEnabled("other", true)
    assert.deepEqual(Array.from(s.commands[0]), ["sh", "app-theme.sh", "enable", "other-script"])
    assert.deepEqual(s.writes, [])
    s.runner.running = false
    s.root.settled = true
    s.root.applyEnabled()
    assert.deepEqual(Array.from(s.commands[1]), ["sh", "app-theme.sh", "sync", "other-script", "background=#123456"])
    s.runner.running = false
    s.root.revert("other")
    assert.deepEqual(Array.from(s.commands[2]), ["sh", "app-theme.sh", "revert", "other-script"])
    s.status({ "other-script": "on" })
    assert.equal(s.root.enabled("other"), true)
    assert.deepEqual(s.writes, [])
})

test("Kitty is independent of Fish and prompt preferences; enabled saved targets still sync", () => {
    const s = service()
    s.root.setEnabled("kitty", true)
    assert.deepEqual(s.writes, [])
    assert.deepEqual(Array.from(s.commands[0]), ["sh", "app-theme.sh", "enable", "kitty", "background=#123456"])
    s.runner.running = false
    s.root.setEnabled("fish", true)
    assert.deepEqual(s.writes, [["appTheme.fish", true]])
    assert.equal(s.root.enabled("prompt"), false)
    s.runner.running = false
    s.root.applyEnabled()
    assert.deepEqual(Array.from(s.commands[2]), ["sh", "app-theme.sh", "sync", "kitty", "background=#123456"])
    assert.deepEqual(Array.from(s.root.queue[0]), ["apply", "fish", "background=#123456"])
})

test("showing the Desktop page refreshes status after external edits", () => {
    const page = fs.readFileSync(process.env.APP_THEME_SETTINGS_SOURCE || locate("modules/sekai/settings/SettingsPageDesktop.qml"), "utf8")
    const handler = page.match(/^    onVisibleChanged: (.*)$/m)
    const onVisibleChanged = new Function("AppThemeService", "visible", handler ? handler[1] : "")
    const s = service()
    onVisibleChanged(s.root, false)
    assert.equal(s.statusProc.running, false)
    onVisibleChanged(s.root, true)
    assert.equal(s.statusProc.running, true)
    assert.deepEqual(s.commands, [])
})
