// node tests/weather-cache-test/weather_cache_test.js   (run from the sekaipop folder)
//
// The lockscreen's weather widget and the desktop weather card are built new at every lock /
// unlock, each with its own WeatherSource, and used to start with no reading. This checks the
// fix: a shared last reading (services/WeatherCache.qml) that a new source starts from, and a
// quick retry after a failed try. Source / logic checks only: Quickshell and the network
// cannot be used here, so the QML has not been run by this test.
const fs = require("fs"), path = require("path"), assert = require("assert")
const top = path.join(__dirname, "..", "..")
const read = rel => fs.readFileSync(path.join(top, rel), "utf8")
let n = 0
const ok = (c, m) => { assert.ok(c, m); n++ }

const cache = read("services/WeatherCache.qml")
const src = read("services/WeatherSource.qml")
const qmlcheck = require("../lib/qmlcheck.js")
ok(qmlcheck(cache, "WeatherCache.qml").length === 0, "WeatherCache.qml passes qmlcheck")
ok(qmlcheck(src, "WeatherSource.qml").length === 0, "WeatherSource.qml passes qmlcheck")

// ---- the cache: run its two functions on their own ----
ok(/^pragma Singleton/.test(cache), "WeatherCache is a singleton")
const fnBody = name => {
    const m = new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}").exec(cache)
    ok(m, "WeatherCache has " + name + "()")
    return m
}
const st = fnBody("store"), gt = fnBody("get")
const root = { location: "", place: null, placeMs: 0, data: null, ms: 0, updatedText: "" }
const store = new Function("root", "return function(" + st[1] + ") {" + st[2] + "}")(root)
const get = new Function("root", "return function(" + gt[1] + ") {" + gt[2] + "}")(root)
ok(get("Majayjay") === null, "empty cache gives nothing")
store("Majayjay", { lat: 1, lon: 2, label: "Majayjay" }, 111, { current: {} }, 222, "Updated 10:00")
const hit = get("Majayjay")
ok(hit && hit.ms === 222 && hit.placeMs === 111 && hit.updatedText === "Updated 10:00", "same Location gets the reading back with its own times")
ok(get("Manila") === null, "another Location gets nothing")
ok(get("") === null, "the automatic Location does not borrow a typed one's reading")

// ---- the source is wired to it ----
ok(/WeatherCache\.store\(root\.location, root\.place, root\.placeMs, data, root\.lastFetchMs, root\.updatedText\)/.test(src),
   "a good fetch is stored")
ok(/function adoptCache\(\)/.test(src) && /WeatherCache\.get\(root\.location\)/.test(src), "adoptCache reads the cache for this Location")
ok(/Component\.onCompleted: root\.adoptCache\(\)/.test(src), "a new source adopts the cache as it is built")
ok(/function refresh\(\) \{\s*if \(root\.loading\)\s*return\s*root\.adoptCache\(\)/.test(src), "refresh() adopts before it asks")
ok(/function refreshIfStale\(\) \{\s*root\.adoptCache\(\)/.test(src), "refreshIfStale() adopts before it judges the age")
ok(/triggeredOnStart: true/.test(src) && /onTriggered: root\.refreshIfStale\(\)/.test(src),
   "the poll's first look skips a fresh reading, and still asks when there is none")
ok(/root\.lastFetchMs = c\.ms/.test(src), "an adopted reading keeps its real age (not \"now\")")

// ---- the retry ----
ok(/function scheduleRetry\(\)/.test(src) && /retryTimer\.interval = 20000 \* Math\.pow\(2, root\.retryCount\)/.test(src), "retries back off from 20 s")
ok(/retryCount >= 5/.test(src), "retries stop after five")
ok(/function fail\(text\) \{[\s\S]*?root\.scheduleRetry\(\)/.test(src), "every failure schedules a retry")
ok(/root\.retryCount = 0\s*\n\s*retryTimer\.stop\(\)/.test(src), "a good reading clears the retry")

// ---- nobody lost the properties the consumers read ----
for (const p of ["temperatureText", "conditionText", "iconName", "areaText", "forecast", "hourly", "lastFetchMs", "polling", "refresh", "refreshIfStale"])
    ok(new RegExp("\\b" + p + "\\b").test(src), "WeatherSource still has " + p)

console.log("weather-cache: " + n + " checks passed")
