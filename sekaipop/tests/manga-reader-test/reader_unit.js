// Rules of the manga reader's reading modes, one by one. Run: node reader_unit.js
const fs = require('fs'), assert = require('assert')
const src = fs.readFileSync(__dirname + '/../../modules/sekai/readers/ReaderMath.js', 'utf8').replace('.pragma library', '')
const M = {}
new Function('M', src + ';Object.assign(M,{MODES,BACKGROUNDS,DEFAULT_PREFS,modeInfo,isMode,normalizePrefs,gridColumns,webtoonFromMeta,looksLikeStrip,resolveMode,orderChapters,chapterNeighbors,trackProgress,LIST_TABS,visibleListTabs,listTabLabel,formatScore,yourScoreText,communityScoreText,shortCount,groupDigits,meanScoreText,sizeText,listProgressText,STATUS_BAR,statusSegments,genreBars,activityGrid,activityCaption,monthMarks,dayText,scoreStamp,scoreBars,statStripCells,activityStats,shelfNote,timeAgo,feedNote,feedRows,countBars,ellipsize,progressFraction,buildSpreads,spreadIndex,aspectOf,fitSize,clampPan,zoomAbout,stepZoom,keyAction,tapAction,keysHint,sanitize,saveName});')(M)
const near = (a, b, m) => assert.ok(Math.abs(a - b) < 1e-6, (m || '') + ': ' + a + ' vs ' + b)

// 1. the seven modes, each with a name, an icon and a family
assert.deepStrictEqual(M.MODES.map(m => m.id), ['paged_ltr', 'paged_rtl', 'paged_v', 'strip', 'strip_gap', 'spread_ltr', 'spread_rtl'])
for (const m of M.MODES) { assert.ok(m.label && m.icon && m.short, m.id); assert.ok(['paged', 'strip', 'spread'].includes(m.family)) }
assert.strictEqual(M.modeInfo('nope').id, 'paged_rtl')
assert.ok(M.modeInfo('strip_gap').gap > 0 && M.modeInfo('strip').gap === 0)
console.log('ok  modes')

// 2. saved settings: junk in, a clean record out; a good record survives a round trip
assert.deepStrictEqual(M.normalizePrefs(null), M.DEFAULT_PREFS)
assert.deepStrictEqual(M.normalizePrefs('x'), M.DEFAULT_PREFS)
let p = M.normalizePrefs({ auto: 'yes', mode: 'banana', webtoonMode: 5, background: 'pink', spreadCover: 1 })
assert.strictEqual(p.auto, false); assert.strictEqual(p.mode, 'paged_rtl'); assert.strictEqual(p.webtoonMode, 'strip')
assert.strictEqual(p.background, 'theme'); assert.strictEqual(p.spreadCover, false)
const good = { auto: false, mode: 'spread_ltr', webtoonMode: 'strip_gap', background: 'white', spreadCover: false, fullWindow: false }
assert.deepStrictEqual(M.normalizePrefs(good), good)
assert.deepStrictEqual(M.normalizePrefs(M.normalizePrefs(good)), good)
// the panel is a full window unless it was set to the side card
assert.strictEqual(M.DEFAULT_PREFS.fullWindow, true)
assert.strictEqual(M.normalizePrefs({}).fullWindow, true)
assert.strictEqual(M.normalizePrefs({ fullWindow: false }).fullWindow, false)
assert.strictEqual(M.normalizePrefs({ fullWindow: 'no' }).fullWindow, false)
console.log('ok  prefs')

// 2b. covers per row: four on the side card, more as the panel widens, capped on a huge screen
assert.strictEqual(M.gridColumns(626, 190, 4, 10), 4)      // the side card (650 wide)
assert.strictEqual(M.gridColumns(0, 190, 4, 10), 4)
assert.strictEqual(M.gridColumns(-5, 190, 4, 10), 4)
assert.strictEqual(M.gridColumns(1200, 190, 4, 10), 6)
assert.strictEqual(M.gridColumns(1876, 190, 4, 10), 9)     // a 1920 px screen at 100 %
assert.strictEqual(M.gridColumns(5000, 190, 4, 10), 10)
assert.strictEqual(M.gridColumns(900), 4)                  // defaults: target 190, 4..4
console.log('ok  grid columns')

// 3. manhwa and friends are long strips on their own
assert.strictEqual(M.webtoonFromMeta('MANHWA', []), true)
assert.strictEqual(M.webtoonFromMeta('Manhwa', null), true)
assert.strictEqual(M.webtoonFromMeta('MANHUA', []), true)
assert.strictEqual(M.webtoonFromMeta('MANGA', []), false)
assert.strictEqual(M.webtoonFromMeta('ONE_SHOT', []), false)
assert.strictEqual(M.webtoonFromMeta('MANGA', ['Action', 'Long Strip']), true, 'a Long Strip tag wins')
assert.strictEqual(M.webtoonFromMeta('', ['Web Comic']), true)
assert.strictEqual(M.webtoonFromMeta('', []), null)
assert.strictEqual(M.webtoonFromMeta(undefined, undefined), null)
// ...and when the metadata is silent the shape of the pages says
const tall = { w: 800, h: 2400 }, page = { w: 900, h: 1300 }
assert.strictEqual(M.looksLikeStrip([], 10), null, 'nothing loaded yet')
assert.strictEqual(M.looksLikeStrip([tall, tall], 10), null, 'needs three')
assert.strictEqual(M.looksLikeStrip([tall, tall, tall], 10), true)
assert.strictEqual(M.looksLikeStrip([page, page, page], 10), false)
assert.strictEqual(M.looksLikeStrip([page, tall, tall, page], 10), true, 'the median decides, one odd page does not')
assert.strictEqual(M.looksLikeStrip([page], 1), false, 'a one-page chapter needs one size')
assert.strictEqual(M.looksLikeStrip([page, page], 2), false)
console.log('ok  webtoon detection')

// 4. auto picks the webtoon mode only for a webtoon, only when auto is on
const pr = M.normalizePrefs({ auto: true, mode: 'paged_rtl', webtoonMode: 'strip_gap' })
assert.strictEqual(M.resolveMode(pr, true), 'strip_gap')
assert.strictEqual(M.resolveMode(pr, false), 'paged_rtl')
assert.strictEqual(M.resolveMode(pr, null), 'paged_rtl')
assert.strictEqual(M.resolveMode(Object.assign({}, pr, { auto: false }), true), 'paged_rtl')
console.log('ok  mode resolution')

// 5. chapter order: the site's index when it has one, else the number; neighbours
const ch = (id, chapter, index) => ({ id, chapter, index })
let list = [ch('c3', '3', 2), ch('c1', '1', 0), ch('c2', '2', 1)]
assert.deepStrictEqual(M.orderChapters(list).map(c => c.id), ['c1', 'c2', 'c3'])
// all indexes 0 (a source that gives none): fall back to the number, 10 after 9 and 9.5 between
list = [ch('a', '10', 0), ch('b', '9', 0), ch('c', '9.5', 0), ch('d', '1', 0)]
assert.deepStrictEqual(M.orderChapters(list).map(c => c.id), ['d', 'b', 'c', 'a'])
// volumes share numbers with chapters: the index keeps them apart
list = [ch('v1', '1', 5), ch('c1', '1', 0), ch('c2', '2', 1)]
assert.deepStrictEqual(M.orderChapters(list).map(c => c.id), ['c1', 'c2', 'v1'])
list = [ch('c3', '3', 2), ch('c1', '1', 0), ch('c2', '2', 1)]
let nb = M.chapterNeighbors(list, 'c2'); assert.strictEqual(nb.prev.id, 'c1'); assert.strictEqual(nb.next.id, 'c3'); assert.strictEqual(nb.pos, 1); assert.strictEqual(nb.current.id, 'c2')
nb = M.chapterNeighbors(list, 'c3'); assert.strictEqual(nb.next, null); assert.strictEqual(nb.prev.id, 'c2')
nb = M.chapterNeighbors(list, 'c1'); assert.strictEqual(nb.prev, null)
nb = M.chapterNeighbors(list, 'zzz'); assert.strictEqual(nb.pos, -1); assert.strictEqual(nb.current, null); assert.strictEqual(nb.next, null); assert.strictEqual(nb.prev, null)
nb = M.chapterNeighbors([], 'x'); assert.strictEqual(nb.total, 0)
const before = JSON.stringify(list); M.orderChapters(list); assert.strictEqual(JSON.stringify(list), before, 'the list is not reordered in place')
console.log('ok  chapter order')

// 6. Tablet spreads
const S = (...w) => w.map(x => x === 'W' ? { w: 1800, h: 1200 } : { w: 900, h: 1300 })
assert.deepStrictEqual(M.buildSpreads(6, [], true), [[0], [1, 2], [3, 4], [5]])
assert.deepStrictEqual(M.buildSpreads(6, [], false), [[0, 1], [2, 3], [4, 5]])
assert.deepStrictEqual(M.buildSpreads(0, [], true), [])
assert.deepStrictEqual(M.buildSpreads(1, [], true), [[0]])
assert.deepStrictEqual(M.buildSpreads(2, [], true), [[0], [1]])
// a landscape page stands alone and moves the pairing
assert.deepStrictEqual(M.buildSpreads(6, S('P', 'P', 'W', 'P', 'P', 'P'), true), [[0], [1], [2], [3, 4], [5]])
assert.deepStrictEqual(M.buildSpreads(5, S('P', 'W', 'P', 'P', 'P'), false), [[0], [1], [2, 3], [4]])
// unknown sizes (a sparse array) count as portrait
const sparse = []; sparse[3] = { w: 2000, h: 1000 }
assert.deepStrictEqual(M.buildSpreads(6, sparse, true), [[0], [1, 2], [3], [4, 5]])
// every page is in exactly one spread, in order
for (const n of [1, 2, 3, 7, 20]) for (const cover of [true, false]) {
    const flat = [].concat(...M.buildSpreads(n, S('P', 'W', 'P', 'P', 'W', 'W', 'P'), cover))
    assert.deepStrictEqual(flat, [...Array(n).keys()], n + ' pages')
}
const sp = M.buildSpreads(6, [], true)
assert.strictEqual(M.spreadIndex(sp, 0), 0); assert.strictEqual(M.spreadIndex(sp, 2), 1); assert.strictEqual(M.spreadIndex(sp, 5), 3)
assert.strictEqual(M.spreadIndex(sp, 99), 3); assert.strictEqual(M.spreadIndex([], 0), 0)
console.log('ok  tablet spreads')

// 7. fitting a page or a spread into a view
let f = M.fitSize(1000, 800, [0.5])            // tall page: height-bound
near(f.h, 800); near(f.w, 400); near(f.widths[0], 400)
f = M.fitSize(1000, 800, [2])                  // wide page: width-bound
near(f.w, 1000); near(f.h, 500)
f = M.fitSize(1000, 800, [0.7, 0.7])           // two pages, same height, joined
near(f.widths[0], f.widths[1]); near(f.w, f.widths[0] + f.widths[1]); assert.ok(f.w <= 1000 + 1e-6 && f.h <= 800 + 1e-6)
f = M.fitSize(500, 800, [0.7, 0.7]); near(f.w, 500); assert.ok(f.h < 800)
f = M.fitSize(0, 800, [0.7]); assert.strictEqual(f.w, 0)
near(M.aspectOf({ w: 300, h: 600 }), 0.5); near(M.aspectOf(null), 0.7); near(M.aspectOf({ w: 0, h: 0 }), 0.7)
console.log('ok  fit')

// 8. pan never leaves a gap, and a page that fits does not move
let q = M.clampPan(1000, 800, 400, 800, 1, 50, 50); assert.deepStrictEqual(q, { panX: 0, panY: 0 })
q = M.clampPan(1000, 800, 400, 800, 3, 9999, -9999)   // 1200 x 2400 in a 1000 x 800 view
near(q.panX, 100); near(q.panY, -800)
q = M.clampPan(1000, 800, 400, 800, 3, 40, 40); near(q.panX, 40); near(q.panY, 40)
console.log('ok  pan')

// 9. zoom about a point keeps that point of the page under the pointer
const V = [1000, 800], C = [600, 800]
let z = M.zoomAbout(V[0], V[1], C[0], C[1], 1, 0, 0, 2, 500, 400, 1, 6)       // centre: no pan
near(z.zoom, 2); near(z.panX, 0); near(z.panY, 0)
z = M.zoomAbout(V[0], V[1], C[0], C[1], 1, 0, 0, 3, 700, 300, 1, 6)           // a point off-centre
const page0 = { x: 700 - (500 + 0) , y: 300 - (400 + 0) }                     // pointer relative to the content centre at zoom 1
const after = { x: 700 - (500 + z.panX), y: 300 - (400 + z.panY) }             // ...at zoom 3
near(after.x, page0.x * 3, 'x follows the pointer'); near(after.y, page0.y * 3, 'y follows the pointer')
z = M.zoomAbout(V[0], V[1], C[0], C[1], 3, 200, 100, 1, 10, 10, 1, 6)         // back to 1: centred again
near(z.zoom, 1); near(z.panX, 0); near(z.panY, 0)
z = M.zoomAbout(V[0], V[1], C[0], C[1], 1, 0, 0, 99, 10, 10, 1, 6); near(z.zoom, 6)
z = M.zoomAbout(V[0], V[1], C[0], C[1], 1, 0, 0, 0.1, 10, 10, 1, 6); near(z.zoom, 1)
// zoomed in on a corner, never a gap
for (const [fx, fy] of [[0, 0], [1000, 800], [0, 800], [1000, 0], [500, 400]]) {
    z = M.zoomAbout(V[0], V[1], C[0], C[1], 1, 0, 0, 4, fx, fy, 1, 6)
    const c2 = M.clampPan(V[0], V[1], C[0], C[1], 4, z.panX, z.panY)
    near(c2.panX, z.panX); near(c2.panY, z.panY)
}
near(M.stepZoom(1, 1, 1, 6), 1.25); near(M.stepZoom(1.25, -1, 1, 6), 1); near(M.stepZoom(6, 1, 1, 6), 6); near(M.stepZoom(1, -1, 1, 6), 1)
near(M.stepZoom(1, -1, 0.4, 3), 0.8); near(M.stepZoom(0.45, -1, 0.4, 3), 0.4)
console.log('ok  zoom')

// 10. keys: W A S D are the arrows; what they do depends on the mode
const act = (mode, key, zoomed) => M.keyAction(mode, key, !!zoomed)
for (const mode of ['paged_ltr', 'spread_ltr']) {
    assert.strictEqual(act(mode, 'right'), 'next'); assert.strictEqual(act(mode, 'left'), 'prev')
    assert.strictEqual(act(mode, 'up'), ''); assert.strictEqual(act(mode, 'down'), '')
}
for (const mode of ['paged_rtl', 'spread_rtl']) {
    assert.strictEqual(act(mode, 'left'), 'next'); assert.strictEqual(act(mode, 'right'), 'prev')
    assert.strictEqual(act(mode, 'up'), ''); assert.strictEqual(act(mode, 'down'), '')
}
assert.strictEqual(act('paged_v', 'down'), 'next'); assert.strictEqual(act('paged_v', 'up'), 'prev')
assert.strictEqual(act('paged_v', 'left'), ''); assert.strictEqual(act('paged_v', 'right'), '')
for (const mode of ['strip', 'strip_gap']) {
    assert.strictEqual(act(mode, 'down'), 'scrollDown'); assert.strictEqual(act(mode, 'up'), 'scrollUp')
    assert.strictEqual(act(mode, 'left'), ''); assert.strictEqual(act(mode, 'right'), '')
    assert.strictEqual(act(mode, 'left', true), 'panLeft'); assert.strictEqual(act(mode, 'down', true), 'scrollDown')
}
// a zoomed page is panned, in every paged mode
for (const mode of ['paged_ltr', 'paged_rtl', 'paged_v', 'spread_ltr', 'spread_rtl']) {
    assert.deepStrictEqual(['left', 'right', 'up', 'down'].map(k => act(mode, k, true)), ['panLeft', 'panRight', 'panUp', 'panDown'], mode)
}
assert.strictEqual(act('paged_ltr', 'bogus'), '')
console.log('ok  keys')

// 11. clicks: the outer thirds turn the page the way the mode reads
assert.strictEqual(M.tapAction('paged_ltr', 50, 400, 1000, 800), 'prev')
assert.strictEqual(M.tapAction('paged_ltr', 950, 400, 1000, 800), 'next')
assert.strictEqual(M.tapAction('paged_ltr', 500, 400, 1000, 800), 'menu')
assert.strictEqual(M.tapAction('paged_rtl', 50, 400, 1000, 800), 'next')
assert.strictEqual(M.tapAction('paged_rtl', 950, 400, 1000, 800), 'prev')
assert.strictEqual(M.tapAction('spread_rtl', 50, 400, 1000, 800), 'next')
assert.strictEqual(M.tapAction('spread_ltr', 50, 400, 1000, 800), 'prev')
assert.strictEqual(M.tapAction('paged_v', 500, 50, 1000, 800), 'prev')
assert.strictEqual(M.tapAction('paged_v', 500, 790, 1000, 800), 'next')
assert.strictEqual(M.tapAction('paged_v', 50, 400, 1000, 800), 'menu')
assert.strictEqual(M.tapAction('strip', 50, 50, 1000, 800), 'menu')
assert.strictEqual(M.tapAction('strip_gap', 950, 790, 1000, 800), 'menu')
console.log('ok  taps')

// 12. the hint under the mode's name matches what the keys really do
for (const mode of M.MODES.map(m => m.id)) assert.ok(M.keysHint(mode).length > 5, mode)
assert.ok(/\u2190 \/ A next/.test(M.keysHint('paged_rtl')) && /\u2192 \/ D next/.test(M.keysHint('paged_ltr')))
console.log('ok  hints')

// 13. file names for a saved page
assert.strictEqual(M.sanitize('A/B: C?'), 'A B C')
assert.strictEqual(M.sanitize('  ...  '), 'manga')
assert.strictEqual(M.sanitize('', 'x'), 'x')
assert.strictEqual(M.sanitize('a'.repeat(200)).length, 80)
let n = M.saveName('Solo Leveling', 'Chapter 12.5', 2)
assert.deepStrictEqual(n, { dir: 'Solo Leveling', base: 'Solo Leveling - Chapter 12.5 - p003' })
n = M.saveName('../../etc', 'a/b', 0); assert.ok(n.dir.indexOf('/') < 0 && n.base.indexOf('/') < 0 && n.dir.indexOf('..') < 0, JSON.stringify(n))
n = M.saveName('', '', 11); assert.strictEqual(n.base, 'manga - chapter - p012')
console.log('ok  save names')

console.log('manga reader: all checks passed')

// ── AniList tracking: the highest chapter / volume read
{
    const chs = [
        { id: 'a', chapter: '1',  kind: 'chapter' }, { id: 'b', chapter: '2',  kind: 'chapter' },
        { id: 'c', chapter: 'Chapter 12.5', kind: 'chapter' }, { id: 'd', chapter: '30', kind: 'chapter' },
        { id: 'e', chapter: '3',  kind: 'volume' },  { id: 'f', chapter: '5',  kind: 'extra' },
    ]
    const only = ids => id => ids.indexOf(id) >= 0
    assert.deepStrictEqual(M.trackProgress(chs, only([])), { progress: 0, volumes: 0 })
    assert.deepStrictEqual(M.trackProgress(chs, only(['a', 'b'])), { progress: 2, volumes: 0 })
    // gaps do not matter: the highest one read counts, a half chapter counts as its whole number
    assert.deepStrictEqual(M.trackProgress(chs, only(['a', 'c'])), { progress: 12, volumes: 0 })
    assert.deepStrictEqual(M.trackProgress(chs, only(['a', 'e', 'f'])), { progress: 1, volumes: 3 })
    assert.deepStrictEqual(M.trackProgress(null, only(['a'])), { progress: 0, volumes: 0 })
    assert.deepStrictEqual(M.trackProgress([{ id: 'x', chapter: 'Prologue', kind: 'chapter' }], only(['x'])), { progress: 0, volumes: 0 })
}
console.log('trackProgress ok')

// ── The Library's AniList lists: tabs (no "All"), scores in the user's format, progress text
{
    assert.deepStrictEqual(M.LIST_TABS.map(t => t.id).slice(0, 4), ['CURRENT', 'COMPLETED', 'DROPPED', 'PLANNING'])
    assert.ok(!M.LIST_TABS.some(t => /all/i.test(t.id) || /all/i.test(t.label)), 'no All tab')
    const ids = c => M.visibleListTabs(c, 'CURRENT').map(t => t.id)
    assert.deepStrictEqual(ids({}), ['CURRENT', 'COMPLETED', 'DROPPED', 'PLANNING'])
    assert.deepStrictEqual(ids(null), ['CURRENT', 'COMPLETED', 'DROPPED', 'PLANNING'])
    assert.deepStrictEqual(ids({ PAUSED: 2 }), ['CURRENT', 'COMPLETED', 'DROPPED', 'PLANNING', 'PAUSED'])
    assert.deepStrictEqual(ids({ PAUSED: 1, REPEATING: 3 }).slice(-2), ['PAUSED', 'REPEATING'])
    // a tab stays while it is the open one, even if it just ran empty
    assert.deepStrictEqual(M.visibleListTabs({}, 'PAUSED').map(t => t.id).slice(-1), ['PAUSED'])
    assert.strictEqual(M.visibleListTabs({ CURRENT: 5 }, 'CURRENT')[0].count, 5)
    assert.strictEqual(M.listTabLabel('CURRENT'), 'Reading')
    assert.strictEqual(M.listTabLabel('REPEATING'), 'Rereading')
    assert.strictEqual(M.listTabLabel('x'), '')

    assert.strictEqual(M.formatScore(10, 100, 'POINT_10'), '10')
    assert.strictEqual(M.formatScore(8, 80, 'POINT_10'), '8')
    assert.strictEqual(M.formatScore(7.5, 75, 'POINT_10_DECIMAL'), '7.5')
    assert.strictEqual(M.formatScore(8, 80, 'POINT_10_DECIMAL'), '8.0')
    assert.strictEqual(M.formatScore(85, 85, 'POINT_100'), '85')
    assert.strictEqual(M.formatScore(4, 80, 'POINT_5'), '4\u2605')
    assert.strictEqual(M.formatScore(3, 100, 'POINT_3'), ':)')
    assert.strictEqual(M.formatScore(2, 66, 'POINT_3'), ':|')
    assert.strictEqual(M.formatScore(1, 33, 'POINT_3'), ':(')
    assert.strictEqual(M.formatScore(0, 0, 'POINT_10'), '', 'no score, nothing shown')
    assert.strictEqual(M.formatScore(null, undefined, ''), '')
    assert.strictEqual(M.formatScore(0, 80, ''), '8.0', 'format not known: 0-100 shown out of 10')

    // the info sheet: your score out of what, the community's, counts, size
    assert.strictEqual(M.yourScoreText(8, 80, 'POINT_10'), '8/10')
    assert.strictEqual(M.yourScoreText(7.5, 75, 'POINT_10_DECIMAL'), '7.5/10')
    assert.strictEqual(M.yourScoreText(85, 85, 'POINT_100'), '85/100')
    assert.strictEqual(M.yourScoreText(4, 80, 'POINT_5'), '4\u2605')
    assert.strictEqual(M.yourScoreText(3, 100, 'POINT_3'), ':)')
    assert.strictEqual(M.yourScoreText(0, 0, 'POINT_10'), '', 'not scored')
    assert.strictEqual(M.yourScoreText(0, 80, ''), '8.0/10', 'format not known')
    assert.strictEqual(M.communityScoreText(85), '8.5')
    assert.strictEqual(M.communityScoreText(0), '')
    assert.strictEqual(M.communityScoreText(null), '')
    assert.strictEqual(M.shortCount(950), '950')
    assert.strictEqual(M.shortCount(1234), '1.2K')
    assert.strictEqual(M.shortCount(2000), '2K')
    assert.strictEqual(M.shortCount(91000), '91K')
    assert.strictEqual(M.shortCount(250000), '250K')
    assert.strictEqual(M.shortCount(1234567), '1.2M')
    assert.strictEqual(M.shortCount(0), '')
    assert.strictEqual(M.sizeText(200, 14), '200 chapters \u00b7 14 volumes')
    assert.strictEqual(M.sizeText(1, 0), '1 chapter')
    assert.strictEqual(M.sizeText(0, 1), '1 volume')
    assert.strictEqual(M.sizeText(0, 0), '')

    assert.strictEqual(M.listProgressText(164, 250), '164/250')
    assert.strictEqual(M.listProgressText(21, 0), '21')
    assert.strictEqual(M.listProgressText(0, 28), '0/28')
    assert.strictEqual(M.listProgressText(null, null), '0')
    assert.strictEqual(M.listProgressText(-3, 5), '0/5')
}

{
    assert.strictEqual(M.groupDigits(12431), '12,431')
    assert.strictEqual(M.groupDigits(999), '999')
    assert.strictEqual(M.groupDigits(1000000), '1,000,000')
    assert.strictEqual(M.groupDigits(0), '0')
    assert.strictEqual(M.groupDigits(null), '0')
    assert.strictEqual(M.meanScoreText(78.4, 'POINT_10'), '7.8')
    assert.strictEqual(M.meanScoreText(78.4, 'POINT_100'), '78')
    assert.strictEqual(M.meanScoreText(0, 'POINT_10'), '')
    assert.strictEqual(M.meanScoreText(null, ''), '')
}
console.log('library lists ok')

// ── the profile page: status bar, taste bars, heatmap
{
    const s = M.statusSegments({ CURRENT: 39, COMPLETED: 100, DROPPED: 10, PLANNING: 537, PAUSED: 0 })
    assert.deepStrictEqual(s.segments.map(x => x.id), ['CURRENT', 'COMPLETED', 'DROPPED', 'PLANNING'])
    assert.strictEqual(s.total, 686)
    near(s.segments.reduce((a, x) => a + x.fraction, 0), 1, 'fractions add up')
    assert.strictEqual(s.segments[0].label, 'Reading')
    assert.deepStrictEqual(M.statusSegments({ PAUSED: 2, REPEATING: 1 }).segments.map(x => x.label), ['Paused', 'Rereading'])
    assert.deepStrictEqual(M.statusSegments({}), { total: 0, segments: [] })
    assert.deepStrictEqual(M.statusSegments(null), { total: 0, segments: [] })
    assert.strictEqual(M.statusSegments({ CURRENT: -4, PLANNING: 'x' }).total, 0)

    const g = M.genreBars([{ genre: 'Action', count: 10, meanScore: 70 }, { genre: 'Romance', count: 20, meanScore: 82 },
                           { genre: '', count: 99 }, { genre: 'Drama', count: 0 }, null], 6, 'POINT_10')
    assert.deepStrictEqual(g.map(x => x.genre), ['Romance', 'Action'])
    near(g[0].fraction, 1); near(g[1].fraction, 0.5)
    assert.strictEqual(g[0].meanText, '8.2'); assert.strictEqual(M.genreBars([{ genre: 'A', count: 3, meanScore: 85 }], 6, 'POINT_100')[0].meanText, '85')
    assert.strictEqual(M.genreBars([{ genre: 'A', count: 3, meanScore: 0 }], 6, 'POINT_10')[0].meanText, '')
    assert.strictEqual(M.genreBars(Array.from({ length: 12 }, (_, i) => ({ genre: 'G' + i, count: i + 1 })), 5).length, 5)
    assert.deepStrictEqual(M.genreBars(null, 6), [])
    assert.deepStrictEqual(M.genreBars([{ genre: 'B', count: 4 }, { genre: 'A', count: 4 }], 6).map(x => x.genre), ['A', 'B'], 'ties in name order')

    // a Wednesday: the last column holds Mon..Wed and then three days that have not come yet
    const today = new Date(2026, 10, 4)               // 2026-11-04 is a Wednesday
    assert.strictEqual(today.getDay(), 3)
    const grid = M.activityGrid({ '2026-11-04': 4, '2026-11-03': 1, '2026-11-05': 9, '2026-05-01': 2, '2020-01-01': 7 }, today, 26)
    assert.strictEqual(grid.cells.length, 26 * 7)
    const at = k => grid.cells.find(c => c.key === k)
    assert.strictEqual(at('2026-11-02').row, 0); assert.strictEqual(at('2026-11-02').col, 25)     // Monday, last column
    assert.strictEqual(at('2026-11-04').row, 2); assert.strictEqual(at('2026-11-04').future, false)
    assert.strictEqual(at('2026-11-05').future, true); assert.strictEqual(at('2026-11-05').count, 0, 'a future day counts nothing')
    assert.strictEqual(at('2026-11-04').level, 4); assert.strictEqual(at('2026-11-03').level, 1)
    assert.strictEqual(grid.max, 4); assert.strictEqual(grid.total, 4 + 1, 'the day before the grid is not counted')
    assert.strictEqual(grid.cells[0].col, 0); assert.strictEqual(grid.cells[0].row, 0)
    assert.strictEqual(grid.cells[0].key, '2026-05-11', 'first Monday: 25 weeks before this one')
    assert.strictEqual(at('2026-05-01'), undefined, 'older than the grid is left out')
    assert.strictEqual(M.activityGrid({}, today, 4).max, 0)
    assert.ok(M.activityGrid({}, today, 4).cells.every(c => c.level === 0))
    // a Sunday ends its own week; a month and a year boundary and a DST change do not shift the rows
    const sun = M.activityGrid({}, new Date(2026, 0, 4), 3)
    assert.strictEqual(sun.cells[sun.cells.length - 1].key, '2026-01-04'); assert.strictEqual(sun.cells[sun.cells.length - 1].row, 6)
    assert.strictEqual(sun.cells[0].key, '2025-12-15')
    const dst = M.activityGrid({}, new Date(2026, 2, 30), 4)
    assert.ok(dst.cells.every((c, i) => c.row === i % 7 && c.col === Math.floor(i / 7)))
    assert.strictEqual(new Set(dst.cells.map(c => c.key)).size, 28, 'every day once')
    // levels are relative to the busiest day
    const lv = M.activityGrid({ '2026-11-02': 10, '2026-11-03': 5, '2026-11-04': 2, '2026-11-01': 1 }, today, 2)
    assert.deepStrictEqual(['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-01'].map(k => lv.cells.find(c => c.key === k).level), [4, 2, 1, 1])
    assert.strictEqual(M.activityCaption(grid), '2 days with a list update in the last 26 weeks')
    assert.strictEqual(M.activityCaption(M.activityGrid({ '2026-11-04': 1 }, today, 1)), '1 day with a list update in the last 1 weeks')
    assert.strictEqual(M.activityCaption(M.activityGrid({}, today, 26)), 'No list updates in the last 26 weeks')

    near(M.progressFraction(164, 250), 0.656); assert.strictEqual(M.progressFraction(5, 0), 0)
    assert.strictEqual(M.progressFraction(300, 250), 1); assert.strictEqual(M.progressFraction(-1, 10), 0)
}
{
    // month marks: one per new month, and none closer than three columns to the one before
    const g = M.activityGrid({}, new Date(2026, 10, 4), 26)
    const marks = M.monthMarks(g)
    assert.ok(marks.length >= 5 && marks.length <= 7, JSON.stringify(marks))
    for (let i = 1; i < marks.length; i++) assert.ok(marks[i].col - marks[i - 1].col >= 3, 'marks apart')
    assert.strictEqual(marks[marks.length - 1].label, 'Nov')
    const labels = marks.map(m => m.label)
    assert.deepStrictEqual(labels, [...new Set(labels)].length === labels.length ? labels : [], 'a month name once')
    assert.ok(M.monthMarks(M.activityGrid({}, new Date(2026, 10, 4), 1)).length === 1)
    const c = g.cells.find(x => x.key === '2026-11-04'); c.count = 3
    assert.strictEqual(M.dayText(c), 'Nov 4 \u00b7 3 updates')
    assert.strictEqual(M.dayText({ key: '2026-01-09', count: 1 }), 'Jan 9 \u00b7 1 update')
    assert.strictEqual(M.dayText({ key: '2026-01-09', count: 0 }), 'Jan 9 \u00b7 no updates')
    assert.strictEqual(M.dayText(null), '')
    assert.strictEqual(M.scoreStamp(10, 100, 'POINT_10'), '\u2605 10')
    assert.strictEqual(M.scoreStamp(8.5, 85, 'POINT_10_DECIMAL'), '\u2605 8.5')
    assert.strictEqual(M.scoreStamp(5, 100, 'POINT_5'), '5\u2605')
    assert.strictEqual(M.scoreStamp(3, 100, 'POINT_3'), ':)')
    assert.strictEqual(M.scoreStamp(0, 0, 'POINT_10'), '')
    assert.strictEqual(M.scoreStamp(0, 90, ''), '\u2605 9.0', 'format not known: 0-100 shown out of 10')
}
console.log('profile page ok')

// ── the profile page: stats strip, score spread, streaks, shelf notes
{
    const b = M.scoreBars({ max: 10, counts: [0, 0, 1, 0, 2, 3, 5, 9, 4, 2] }, 'POINT_10')
    assert.strictEqual(b.bars.length, 10); assert.strictEqual(b.rated, 26)
    assert.strictEqual(b.peak, 7, 'the busiest score is the 8'); near(b.bars[7].fraction, 1); near(b.bars[2].fraction, 1 / 9)
    assert.deepStrictEqual(b.bars.map(x => x.label), ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'])
    const st = M.scoreBars({ max: 5, counts: [0, 1, 0, 4, 2] }, 'POINT_5')
    assert.deepStrictEqual(st.bars.map(x => x.label), ['1\u2605', '2\u2605', '3\u2605', '4\u2605', '5\u2605'])
    assert.deepStrictEqual(M.scoreBars({ max: 3, counts: [1, 2, 3] }, 'POINT_3').bars.map(x => x.label), [':(', ':|', ':)'])
    assert.deepStrictEqual(M.scoreBars(null, 'POINT_10'), { rated: 0, peak: -1, bars: [] })
    assert.deepStrictEqual(M.scoreBars({ max: 10, counts: [] }, ''), { rated: 0, peak: -1, bars: [] })
    const none = M.scoreBars({ max: 3, counts: [0, 0, 0] }, 'POINT_3')
    assert.strictEqual(none.rated, 0); assert.strictEqual(none.peak, -1); assert.ok(none.bars.every(x => x.fraction === 0))
    assert.strictEqual(M.scoreBars({ max: 3, counts: [2, 'x', -4] }, '').rated, 2, 'bad counts are zero')

    const cells = M.statStripCells({ count: 600, chaptersRead: 41000, volumesRead: 1234 }, { COMPLETED: 412 }, 380)
    assert.deepStrictEqual(cells.map(c => c.label), ['Volumes read', 'Completed', 'Scored', 'Chapters per title'])
    assert.deepStrictEqual(cells.map(c => c.value), ['1,234', '412', '380', '68'])
    assert.deepStrictEqual(M.statStripCells(null, null, 0).map(c => c.value), ['\u2014', '\u2014', '\u2014', '\u2014'])
    assert.strictEqual(M.statStripCells({ count: 0, chaptersRead: 0, volumesRead: 0 }, { COMPLETED: 0 }, 0)[3].value, '\u2014', 'no division by zero')

    // Wednesday 2026-11-04: a three-day streak that includes today, an older run of two, a busy day
    const today = new Date(2026, 10, 4)
    const g1 = M.activityGrid({ '2026-11-04': 2, '2026-11-03': 1, '2026-11-02': 4, '2026-10-20': 1, '2026-10-19': 1, '2026-10-05': 9, '2026-10-30': 1 }, today, 26)
    const a1 = M.activityStats(g1, today)
    assert.strictEqual(a1.current, 3); assert.strictEqual(a1.longest, 3)
    assert.strictEqual(a1.week, 2 + 1 + 4, 'Monday to today'); assert.strictEqual(a1.month, 2 + 1 + 4, 'Nov 2-4 only: Oct 30 is last month')
    assert.deepStrictEqual(a1.busiest, { key: '2026-10-05', count: 9 })
    // today empty: the streak is still alive and ends yesterday
    const a2 = M.activityStats(M.activityGrid({ '2026-11-03': 1, '2026-11-02': 1 }, today, 26), today)
    assert.strictEqual(a2.current, 2)
    // a gap yesterday and today: it is over
    const a3 = M.activityStats(M.activityGrid({ '2026-11-02': 1, '2026-10-31': 5, '2026-10-30': 5, '2026-10-29': 5 }, today, 26), today)
    assert.strictEqual(a3.current, 0); assert.strictEqual(a3.longest, 3)
    // nothing at all, and no grid
    const a4 = M.activityStats(M.activityGrid({}, today, 26), today)
    assert.deepStrictEqual(a4, { current: 0, longest: 0, week: 0, month: 0, busiest: null })
    assert.deepStrictEqual(M.activityStats(null, today), { current: 0, longest: 0, week: 0, month: 0, busiest: null })
    // the future days after today never count, even if the server sent them
    const a5 = M.activityStats(M.activityGrid({ '2026-11-04': 1, '2026-11-05': 9, '2026-11-06': 9 }, today, 26), today)
    assert.strictEqual(a5.current, 1); assert.strictEqual(a5.longest, 1); assert.strictEqual(a5.busiest.count, 1)

    assert.strictEqual(M.shelfNote('almost', { left: 3 }), '3 ch. left')
    assert.strictEqual(M.shelfNote('almost', { left: 0 }), '')
    assert.strictEqual(M.shelfNote('stalled', { progress: 12, idleDays: 45 }), 'Ch. 12 \u00b7 45d')
    assert.strictEqual(M.shelfNote('stalled', { progress: 0, idleDays: 31 }), 'Not started \u00b7 31d')
    assert.strictEqual(M.shelfNote('planning', { left: 3 }), '')
    assert.strictEqual(M.shelfNote('almost', null), '')
}
console.log('profile extras ok')

// ── the profile page: breakdown bars, the activity feed, time words
{
    assert.strictEqual(M.timeAgo(1000, 990), 'now'); assert.strictEqual(M.timeAgo(1000, 1000 + 500), 'now', 'a clock that is ahead is just now')
    assert.strictEqual(M.timeAgo(10000, 10000 - 120), '2m'); assert.strictEqual(M.timeAgo(10000, 10000 - 50), '1m')
    assert.strictEqual(M.timeAgo(100000, 100000 - 7200), '2h'); assert.strictEqual(M.timeAgo(1e6, 1e6 - 86400 * 3), '3d')
    assert.strictEqual(M.timeAgo(1e8, 1e8 - 86400 * 65), '2mo'); assert.strictEqual(M.timeAgo(1e9, 1e9 - 86400 * 800), '2y')
    assert.strictEqual(M.timeAgo(1000, 0), ''); assert.strictEqual(M.timeAgo(1000, 'x'), '')

    const now = 100000
    assert.strictEqual(M.feedNote({ status: 'read chapter', progress: '52', createdAt: now - 7200 }, now), 'Ch. 52 \u00b7 2h')
    assert.strictEqual(M.feedNote({ status: 'read chapter', progress: '52 - 54', createdAt: now - 7200 }, now), 'Ch. 52 - 54 \u00b7 2h')
    assert.strictEqual(M.feedNote({ status: 'completed', progress: '', createdAt: now - 86400 }, now), 'Completed \u00b7 1d')
    assert.strictEqual(M.feedNote({ status: 'plans to read', createdAt: now - 3600 }, now), 'Planned \u00b7 1h')
    assert.strictEqual(M.feedNote({ status: 'dropped', createdAt: now - 3600 }, now), 'Dropped \u00b7 1h')
    assert.strictEqual(M.feedNote({ status: 'paused reading', createdAt: now - 3600 }, now), 'Paused \u00b7 1h')
    assert.strictEqual(M.feedNote({ status: 're-read chapter', progress: '3', createdAt: now - 3600 }, now), 'Reread Ch. 3 \u00b7 1h', 're-read is not a plain read')
    assert.strictEqual(M.feedNote({ status: 'rewatching', createdAt: now - 3600 }, now), 'Rewatching \u00b7 1h', 'unknown words shown as they are')
    assert.strictEqual(M.feedNote({ status: '', progress: '8', createdAt: now - 3600 }, now), 'Ch. 8 \u00b7 1h')
    assert.strictEqual(M.feedNote({ status: 'read chapter', progress: '5' }, now), 'Ch. 5', 'no time: the words alone')
    assert.strictEqual(M.feedNote(null, now), '')
    const rows = M.feedRows([{ id: 'al:1', title: 'A', image: 'i', status: 'read chapter', progress: '2', createdAt: now - 60 }, null, { title: 'no id' }], now)
    assert.deepStrictEqual(rows, [{ id: 'al:1', title: 'A', image: 'i', note: 'Ch. 2 \u00b7 1m' }])
    assert.deepStrictEqual(M.feedRows(null, now), [])
    assert.strictEqual(M.shelfNote('feed', rows[0]), 'Ch. 2 \u00b7 1m'); assert.strictEqual(M.shelfNote('feed', {}), '')

    const cb = M.countBars([{ label: 'Romance', count: 30, meanScore: 81.5 }, { label: 'Drama', count: 15, meanScore: 0 },
                            { label: '', count: 9 }, { label: 'Zero', count: 0 }, null, { label: 'Odd', count: 3, url: 'https://anilist.co/staff/7' }], 8, 'POINT_10')
    assert.deepStrictEqual(cb.map(x => x.label), ['Romance', 'Drama', 'Odd'], 'order kept, empty rows dropped')
    near(cb[0].fraction, 1); near(cb[1].fraction, 0.5); near(cb[2].fraction, 0.1)
    assert.strictEqual(cb[0].note, '30  \u00b7  \u2605 8.2'); assert.strictEqual(cb[1].note, '15'); assert.strictEqual(cb[2].url, 'https://anilist.co/staff/7')
    assert.strictEqual(M.countBars([{ label: 'A', count: 2, meanScore: 85 }], 8, 'POINT_100')[0].note, '2  \u00b7  \u2605 85')
    assert.strictEqual(M.countBars(Array.from({ length: 12 }, (_, i) => ({ label: 'L' + i, count: i + 1 })), 5).length, 5)
    assert.deepStrictEqual(M.countBars(null, 5), [])
    assert.strictEqual(M.ellipsize('Short', 10), 'Short'); assert.strictEqual(M.ellipsize('Berserk of Gluttony Again', 12), 'Berserk of\u2026')
    assert.strictEqual(M.ellipsize(null, 5), '')
}
console.log('profile extras 2 ok')
