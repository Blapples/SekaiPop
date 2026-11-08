// Run with: node tests/novel-discover-test/discover_unit.js
// The novel reader's Discover filters (NovelMath.js): the options, the query the backend is asked
// with, the count on the filter key. NovelMath.js is a QML JS library: load it as plain script text.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "..", "modules", "sekai", "readers", "NovelMath.js"), "utf8")
const N = new Function(src.replace(/^\.pragma library/m, "") + `
return { DISCOVER_SORTS, GENRES, COUNTRIES, STATUSES, SCORE_MIN, SCORE_MAX, LENGTHS,
         yearOptions, lengthRange, discoverQuery, discoverFilterCount, lengthText, cardMeta,
         normTitle, matchScore, rankCandidates, BEST_MIN }`)()

const none = { query: "", sort: "TRENDING_DESC", genres: [], tags: [], country: "", statuses: [],
               scoreMin: 0, scoreMax: 0, year: 0, length: "", adult: false, page: 1 }

// nothing on: a page and a sort, nothing else
assert.strictEqual(N.discoverQuery(none), "page=1&sort=TRENDING_DESC")
assert.strictEqual(N.discoverFilterCount(none), 0)
assert.strictEqual(N.discoverQuery({}), "page=1")                    // an empty state does not throw
assert.strictEqual(N.discoverFilterCount({}), 0)

// every filter is in the query, in the form the backend reads
const all = Object.assign({}, none, {
    sort: "SCORE_DESC", genres: ["Fantasy", "Slice of Life"], tags: ["Isekai", "Time Skip"],
    country: "KR", statuses: ["RELEASING", "HIATUS"], scoreMin: 70, scoreMax: 90, year: 2020,
    length: "vol-mid", adult: true, page: 3 })
assert.strictEqual(N.discoverQuery(all),
    "page=3&sort=SCORE_DESC&genres=Fantasy%2CSlice%20of%20Life&tags=Isekai%7CTime%20Skip&country=KR"
    + "&status=RELEASING,HIATUS&score_min=70&score_max=90&year=2020&vol_min=4&vol_max=10&adult=1")
assert.strictEqual(N.discoverFilterCount(all), 2 + 2 + 2 + 1 + 1 + 1 + 1 + 1 + 1)

// a typed search goes by best match: no sort in the URL, the filters stay
const typed = Object.assign({}, none, { query: "  re zero ", genres: ["Drama"] })
assert.strictEqual(N.discoverQuery(typed), "page=1&q=re%20zero&genres=Drama")

// the sort is not a filter, and a page below 1 is page 1
assert.strictEqual(N.discoverFilterCount(Object.assign({}, none, { sort: "SCORE_DESC", query: "x" })), 0)
assert.strictEqual(N.discoverQuery(Object.assign({}, none, { page: 0 })).indexOf("page=1"), 0)

// length: volumes for light novels, chapters for web novels; "any" asks for nothing
const lr = k => N.lengthRange(k)
assert.deepStrictEqual(lr(""), { volMin: 0, volMax: 0, chMin: 0, chMax: 0 })
assert.deepStrictEqual(lr("vol-short"), { volMin: 0, volMax: 3, chMin: 0, chMax: 0 })
assert.deepStrictEqual(lr("vol-long"), { volMin: 11, volMax: 0, chMin: 0, chMax: 0 })
assert.deepStrictEqual(lr("ch-mid"), { volMin: 0, volMax: 0, chMin: 101, chMax: 500 })
assert.deepStrictEqual(lr("ch-long"), { volMin: 0, volMax: 0, chMin: 501, chMax: 0 })
assert.deepStrictEqual(lr("nonsense"), { volMin: 0, volMax: 0, chMin: 0, chMax: 0 })
const q = k => N.discoverQuery(Object.assign({}, none, { length: k }))
assert.ok(q("vol-short").endsWith("&vol_max=3") && q("vol-short").indexOf("vol_min") < 0)
assert.ok(q("ch-long").endsWith("&ch_min=501") && q("ch-long").indexOf("ch_max") < 0)
assert.ok(q("ch-short").endsWith("&ch_max=100"))
// the ranges do not overlap or leave a gap
assert.strictEqual(lr("vol-short").volMax + 1, lr("vol-mid").volMin)
assert.strictEqual(lr("vol-mid").volMax + 1, lr("vol-long").volMin)
assert.strictEqual(lr("ch-short").chMax + 1, lr("ch-mid").chMin)
assert.strictEqual(lr("ch-mid").chMax + 1, lr("ch-long").chMin)

// the option lists
const values = list => list.map(o => o.value)
assert.deepStrictEqual(values(N.COUNTRIES), ["", "JP", "KR", "CN", "TW"])
assert.deepStrictEqual(values(N.DISCOVER_SORTS), ["TRENDING_DESC", "POPULARITY_DESC", "SCORE_DESC", "FAVOURITES_DESC", "START_DATE_DESC"])
assert.ok(!values(N.DISCOVER_SORTS).includes("SEARCH_MATCH"))
assert.strictEqual(new Set(values(N.LENGTHS)).size, N.LENGTHS.length)
assert.strictEqual(N.GENRES.length, 18)
assert.strictEqual(N.SCORE_MIN[0].value, 0)
assert.strictEqual(N.SCORE_MAX[0].value, 0)
const years = N.yearOptions(2026)
assert.strictEqual(years.length, 41)
assert.deepStrictEqual(years[0], { label: "Any", value: 0 })
assert.deepStrictEqual(years[1], { label: "2026", value: 2026 })
assert.deepStrictEqual(years[40], { label: "1987", value: 1987 })

// card text
assert.strictEqual(N.lengthText({ volumes: 5, chapters: 0 }), "5 vols")
assert.strictEqual(N.lengthText({ volumes: 1, chapters: 0 }), "1 vol")
assert.strictEqual(N.lengthText({ volumes: 0, chapters: 550 }), "550 ch")
assert.strictEqual(N.lengthText({ volumes: 5, chapters: 40 }), "5 vols · 40 ch")
assert.strictEqual(N.lengthText({ volumes: 0, chapters: 0 }), "")
assert.strictEqual(N.lengthText(null), "")
assert.strictEqual(N.cardMeta({ year: 2018, status: "Releasing" }), "2018 · Releasing")
assert.strictEqual(N.cardMeta({ year: 0, status: "Finished" }), "Finished")
assert.strictEqual(N.cardMeta({ year: 0, status: "" }), "")

// the length options have a short text for the filter key
assert.ok(N.LENGTHS.every(o => typeof o.chip === "string" && o.chip.length > 0 && o.chip.length <= 14))
assert.strictEqual(new Set(N.LENGTHS.map(o => o.chip)).size, N.LENGTHS.length)

// finding a Discover title in the source
assert.strictEqual(N.normTitle("  Re:ZERO -Starting Life!- "), "re zero starting life")
assert.strictEqual(N.normTitle("Café Ñandú"), "cafe nandu")
assert.strictEqual(N.normTitle(null), "")
assert.strictEqual(N.normTitle("無職転生"), "無職転生")                       // Japanese stays
const names = ["Re:ZERO -Starting Life in Another World-", "Re:Zero kara Hajimeru Isekai Seikatsu", "Re Zero Light Novel"]
assert.strictEqual(N.matchScore("Re:Zero kara Hajimeru Isekai Seikatsu", names), 1)        // any of the names
assert.strictEqual(N.matchScore("re zero light novel", names), 1)                          // case and marks do not matter
assert.strictEqual(N.matchScore("Re:Zero Starting Life in Another World Vol 1", names), 0.85)   // inside / contains
const sim = N.matchScore("Another World Starting Over", names)
assert.ok(sim > 0 && sim < 0.85, "shared words only: " + sim)
assert.strictEqual(N.matchScore("Omniscient Reader", names), 0)
assert.strictEqual(N.matchScore("", names), 0)
assert.strictEqual(N.matchScore("x", []), 0)
assert.strictEqual(N.matchScore("ab", ["abc"]), 0, "two letters inside a longer name is not a match")
const rows = N.rankCandidates([
    { id: "a", title: "Omniscient Reader" },
    { id: "b", title: "Re:Zero Starting Life in Another World Vol 1" },
    { id: "c", title: "Another World Starting Over" },
    { id: "d", title: "Re:Zero kara Hajimeru Isekai Seikatsu" }], names)
assert.deepStrictEqual(rows.map(r => r.id), ["d", "b", "c", "a"])
assert.strictEqual(rows[0].best, true)
assert.ok(rows.slice(1).every(r => r.best === false))
assert.strictEqual(rows[0].title, "Re:Zero kara Hajimeru Isekai Seikatsu")           // the row keeps its fields
assert.ok(!("_i" in rows[0]))
// nothing close: nothing is marked; ties keep the source's own order
const far = N.rankCandidates([{ id: "x", title: "Foo" }, { id: "y", title: "Bar" }], names)
assert.deepStrictEqual(far.map(r => r.id), ["x", "y"])
assert.ok(far.every(r => r.best === false))
assert.deepStrictEqual(N.rankCandidates([], names), [])
assert.deepStrictEqual(N.rankCandidates(null, names), [])
assert.strictEqual(N.BEST_MIN, 0.85)

console.log("novel discover: ok")
