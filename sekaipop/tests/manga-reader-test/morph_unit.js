// The readers' grow / shrink, their two ways of going away (minimize, close) and their window,
// read as text (Node can't load QML).
// Run: node tests/manga-reader-test/morph_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const panel = read("modules/sekai/readers/ReaderPanel.qml")
const host = read("modules/sekai/readers/ReaderHost.qml")
const novel = read("modules/sekai/readers/NovelReader.qml")

// The window has a namespace the shell's no-anim layer rule (^sekaipop-) matches; with a colon
// or another prefix Hyprland's own layer animation plays on top of the grow / shrink.
for (const [name, src] of [["ReaderHost", host]]) {
    const m = src.match(/WlrLayershell\.namespace:\s*"([^"]+)"/)
    assert(m, name + " has no namespace")
    assert(/^sekaipop-/.test(m[1]), name + " namespace \"" + m[1] + "\" does not start with sekaipop-")
}

// Nothing heavy happens on the first frame of the shrink: the texture is made first, the catcher
// does not take the hover, and the input region holds still while the card moves.
assert(/easing\.type:\s*Easing\.InOutCubic/.test(panel), "the shrink is eased at both ends")
assert(/layer\.enabled:\s*root\.useLayer\s*&&\s*\(popIn\.running\s*\|\|\s*swallow\.running\s*\|\|\s*root\.warming\)/.test(panel), "the layer must be on while warming")
assert(/layer\.mipmap:\s*false/.test(panel), "no mipmaps on the card's texture")
assert(/id:\s*warmTimer[\s\S]{0,80}interval:\s*\d+[\s\S]{0,120}swallow\.restart\(\)/.test(panel), "the shrink must start from the warm-up timer")
const catcher = panel.match(/MouseArea\s*\{[^}]*visible:\s*!root\.open[^}]*\}/)
assert(catcher && /hoverEnabled:\s*false/.test(catcher[0]), "the catcher must not take the hover")
assert(/readonly property bool animating:\s*popIn\.running\s*\|\|\s*swallow\.running/.test(panel) && /readonly property bool holding:\s*root\.animating\s*\|\|\s*root\.resizing/.test(panel) && /x:\s*root\.holding/.test(panel), "the input region must hold still while animating or resizing")

// Changing width (the size key, a chapter going full-screen): the reader follows the card live
// (the content morphs with it), the width is moved by the frame counter with a cap on one frame's
// share (a long frame must not make it jump ahead), and what is costly to redo on every frame
// holds still meanwhile: the header's halftone Canvas and the wrapped titles of every cover.
assert(!/Behavior on implicitWidth/.test(panel), "the width is not animated by a plain Behavior")
assert(/implicitWidth:\s*root\.shownWidth/.test(panel) && /onTargetWidthChanged/.test(panel), "the panel's width follows a shown width that is moved toward the target")
assert(/FrameAnimation\s*\{[\s\S]{0,120}running:\s*root\.resizing[\s\S]{0,200}Math\.min\(frameTime,\s*1 \/ 30\)/.test(panel), "the move is frame-driven and a long frame counts for a capped share")
assert(/id:\s*body\s*\n\s*Layout\.fillWidth:\s*true/.test(panel) && !/bodyWidth|bodySlot/.test(panel), "the body follows the card live")
assert(/onResizingChanged:\s*ReaderEnv\.panelResizing\s*=\s*root\.resizing/.test(panel), "the panel tells the readers it is changing width")
assert(/property bool panelResizing:\s*false/.test(read("modules/sekai/readers/ReaderEnv.qml")), "ReaderEnv carries the flag")
assert(/id:\s*plate[\s\S]{0,400}dotsLive:\s*!root\.resizing/.test(panel), "the header's halftone holds still while the width moves")
const dots = read("modules/common/widgets/DotField.qml")
assert(/property bool live:\s*true/.test(dots) && /onWidthChanged:\s*if \(live\) requestPaint\(\)/.test(dots) && /onLiveChanged:\s*if \(live\) requestPaint\(\)/.test(dots), "a DotField is not painted for every width while it is not live, and is once when it is again")
const plateW = read("modules/common/widgets/SekaiPlate.qml")
assert(/property bool dotsLive:\s*true/.test(plateW) && /live:\s*root\.dotsLive/.test(plateW) && /opacity:\s*root\.dotsLive \? 1 : 0\.01/.test(plateW), "the plate hides the halftone while it is not live")
const cover = read("modules/sekai/readers/CoverCard.qml")
assert(/property real titleWidth:\s*titleWidthNow/.test(cover) && /if \(!root\.holdTitle \|\| !ReaderEnv\.panelResizing\) root\.titleWidth = root\.titleWidthNow/.test(cover) && (cover.match(/width:\s*root\.titleWidth/g) || []).length === 2, "a cover's titles keep their width while the panel changes width")
assert(/root\.fullTitle \? titleColumn\.implicitHeight \+ 34 : root\.stripHeight/.test(cover) && !/height:\s*titleColumn\.implicitHeight \+ 14/.test(cover) && /readonly property real stripHeight:\s*2 \* root\.titleLineHeight/.test(cover), "a cover's title strip has one height, so a title wrapping differently does not change the cover's height")
assert(/readonly property bool hovered:\s*tap\.containsMouse && !ReaderEnv\.panelResizing/.test(cover), "no cover plays its hover while the panel changes width")
assert(/property bool fullTitle:\s*false/.test(cover) && /property bool holdTitle:\s*true/.test(cover) && /maximumLineCount:\s*root\.fullTitle \? 2147483647 : 2/.test(cover) && /elide:\s*root\.fullTitle \? Text\.ElideNone : Text\.ElideRight/.test(cover), "a cover can show its whole title over the cover, with no line limit and no elision")
assert(/height:\s*clipBox\.height - \(root\.fullTitle \? 0 : titleBar\.height\) - root\.footerHeight/.test(cover), "with the whole title over the cover, the cover is the same height for every title")
assert(/property real panelBodyTarget/.test(read("modules/sekai/readers/ReaderEnv.qml")) && /ReaderEnv\.panelBodyTarget = root\.targetWidth - 2 \* root\.margin/.test(panel), "the panel says what body width the move ends at")
for (const [f, g] of [["BrowseView", "mangaGrid"], ["LibraryView", "libGrid"]]) {
    const v = read("modules/sekai/readers/manga/" + f + ".qml")
    const grid = v.match(new RegExp("id:\\s*" + g + "[\\s\\S]{0,900}"))
    assert(grid && /width:\s*ReaderEnv\.panelResizing \? Math\.max\(0, Math\.round\(ReaderEnv\.panelBodyTarget\)/.test(grid[0]), f + ": the grid keeps the width the move ends at while the panel changes width")
    assert(/fullTitle:\s*true/.test(v) && /holdTitle:\s*false/.test(v), f + ": covers show their whole title and take their width at once")
}
for (const f of ["manga", "novel"]) {
    const dv = read("modules/sekai/readers/" + f + "/DetailView.qml")
    assert(/live:\s*!ReaderEnv\.panelResizing/.test(dv), f + " title page: the hero's halftone holds still too")
}
console.log("reader resize: all checks passed")
console.log("reader grow / shrink: all checks passed")

// No tab on the edge any more: nothing of it is left in the panel or the host, and a hidden panel
// takes no input at all.
assert(!/viaTab|tabArea|tabHovered|tabPress|tabIcon|tabHoldTimer|restoreRequested|requestRestore|restoreAsked/.test(panel), "no tab on the edge may be left in the panel")
assert(!/restoreRequested|MinimizedDock|readers-tabs/.test(host), "the host must not wait for a click on a tab")
assert(!fs.existsSync(path.join(root, "modules/sekai/readers/MinimizedDock.qml")), "the dock window must be gone")
assert(!/tabIcon/.test(novel), "the novel reader must not set the removed tabIcon")
const hitBlock = panel.match(/Item\s*\{\s*id:\s*hit[\s\S]*?\n    \}\n/)
assert(hitBlock && !/MouseArea/.test(hitBlock[0]) && !/minimized/.test(hitBlock[0].replace(/\/\/.*\n/g, "")), "a hidden or minimized panel has no rectangle for the pointer")
// the end of the shrink is the bare edge, in both cases
assert(/readonly property real endL:\s*root\.onLeft \? 0 : root\.width/.test(panel) && /readonly property real endT:\s*root\.height \/ 2/.test(panel), "the card shrinks into a point on its screen edge")
console.log("reader without a tab: all checks passed")

// Two keys in the header: minimize (kept running) and close (unloaded), as HeaderKeys.
assert(/HeaderKey\s*\{\s*icon:\s*"remove"\s*\n\s*onClicked:\s*root\.minimize\(\)/.test(panel), "the header must have a minimize key")
assert(/HeaderKey\s*\{\s*icon:\s*"close"\s*\n\s*onClicked:\s*root\.close\(\)/.test(panel), "the header must have a close key")
const minFn = panel.match(/function minimize\(\)\s*\{[\s\S]*?\n    \}/)
assert(minFn && /pendingMinimize = true/.test(minFn[0]) && /open = false/.test(minFn[0]), "minimize must hide the card and keep the panel")
const closeFn = panel.match(/function close\(\)\s*\{[\s\S]*?\n    \}/)
assert(closeFn && /pendingMinimize = false/.test(closeFn[0]) && /open = false/.test(closeFn[0]), "close must hide the card and not keep the panel")
// `minimized` is only raised once the card has reached the edge, so the host never unloads it in between
assert(/id:\s*swallow[\s\S]*?if \(root\.pendingMinimize\)\s*\{[\s\S]*?root\.minimized = true/.test(panel), "minimized is set when the shrink has finished")
// the panel stays mapped and loaded while minimized
assert(/visible:\s*root\.reveal\s*>\s*0\.001\s*\|\|\s*root\.minimized\s*\|\|\s*root\.pendingMinimize/.test(panel), "the panel stays visible (mapped) while minimized")
assert(/slot\.open \|\| \(slot\.item \? \(slot\.item\.reveal > 0\.001 \|\| slot\.item\.settling \|\| slot\.item\.minimized\)/.test(host), "the host keeps its window while a panel is minimized")
// coming back: drawn once (faint), then grown; `minimized` is dropped by the panel, after reveal is raised
assert(/const fromMin = root\.minimized[\s\S]*?root\.reveal = 0\.002[\s\S]*?root\.minimized = false[\s\S]*?restoreWarm\.restart\(\)/.test(panel), "the way back warms the card before it grows")
assert(/id:\s*restoreWarm[\s\S]*?popIn\.restart\(\)/.test(panel), "the grow starts after the warm-up")
assert(/opacity:\s*\(root\.warming && root\.open\) \? 0\.01 : 1/.test(panel), "the warm-up drawing is faint, not skipped")
console.log("reader minimize / close keys: all checks passed")

// The host: minimize keeps the slot loaded, close unloads it, and the shortcut brings it back.
const slot = host.match(/component ReaderSlot: Loader \{[\s\S]*?\n    \}\n\n    function open/)
assert(slot, "ReaderSlot not found")
assert(/function minimize\(\)\s*\{\s*if \(open && item\)\s*item\.minimize\(\)/.test(slot[0]), "slot.minimize calls the panel's minimize")
assert(/function close\(\)\s*\{[\s\S]*?item\.close\(\)[\s\S]*?item\.minimized\)\s*\{[\s\S]*?unloadTimer\.start\(\)/.test(slot[0]), "slot.close closes an open panel and unloads a minimized one")
assert(/function hide\(\)\s*\{\s*close\(\)/.test(slot[0]), "hide is close")
assert(/unloadTimer[\s\S]*?!slot\.open && !slot\.item\?\.minimized\) slot\.active = false/.test(slot[0]), "a minimized panel is not unloaded")
const showFn = slot[0].match(/function show\(\)[\s\S]*?\n        \}\n/)
assert(showFn && /item\.open = true/.test(showFn[0]) && !/item\.minimized = false/.test(showFn[0]), "show brings a minimized panel back by opening it")
for (const n of ["manga", "novel"]) {
    const h = host.match(new RegExp('target: "' + n + 'reader"[\\s\\S]*?\\n    \\}\\n'))
    assert(h, n + " ipc handler not found")
    for (const fn of ["toggle", "show", "hide", "minimize", "close"])
        assert(new RegExp("function " + fn + "\\(\\): void").test(h[0]), n + "reader ipc needs " + fn)
}
console.log("reader host: all checks passed")

// The header is one family: the keys, the switch and the profile key are the same height, flat
// dark capsules, and the toolbar's Filters chip is as tall as the search pill beside it.
// A size is a number or a ReaderType token (ReaderType.hField), which is looked up in ReaderType.qml.
const rType = read("modules/sekai/readers/ReaderType.qml")
const tok = v => /^\d+$/.test(v) ? parseInt(v) : parseInt((rType.match(new RegExp("property int " + v.split(".")[1] + ":\\s*(\\d+)")) || [])[1])
const num = (src, re, what) => { const m = src.match(re); assert(m, what + " not found"); const v = tok(m[1]); assert(v > 0, what + " is not a number"); return v }
const hk = read("modules/sekai/readers/HeaderKey.qml")
const hkH = num(hk, /implicitHeight:\s*(\d+|ReaderType\.\w+)/, "HeaderKey height")
assert(hkH >= 40, "the header keys must be big (40 or more)")
assert(num(read("modules/sekai/readers/manga/AccountKey.qml"), /implicitHeight:\s*(\d+|ReaderType\.\w+)/, "AccountKey height") === hkH, "the profile key is as tall as the header keys")
assert(num(panel, /SegmentSwitch\s*\{[\s\S]*?height:\s*(\d+)/, "switch height") === hkH, "the Browse / Library switch is as tall as the header keys")
assert(num(panel, /id:\s*headerExtra[\s\S]*?height:\s*(\d+)/, "headerExtra height") === hkH, "the extra slot is as tall as the header keys")
assert(num(panel, /id:\s*plate[\s\S]*?height:\s*(\d+) \+ Theme\.shadowOffset/, "plate height") >= hkH + 12, "the plate leaves room round the keys")
assert(!/SettingRoundButton/.test(panel + read("modules/sekai/readers/MangaReader.qml")), "no diamond keys are left in the header")
const mangaReader = read("modules/sekai/readers/MangaReader.qml")
const acct = read("modules/sekai/readers/manga/AccountKey.qml")
assert(/headerData:\s*AccountKey\s*\{[\s\S]*?anilistLogin\.open\(\)/.test(mangaReader), "the manga header's account key is the profile key")
assert(/Manga\.alViewer\.name/.test(acct) && /Manga\.alViewer\.avatar/.test(acct), "the profile key shows the viewer's name and avatar")
assert(/"Log in"/.test(acct), "the profile key says Log in while logged out")
for (const f of ["BrowseView", "LibraryView"]) {
    const v = read("modules/sekai/readers/manga/" + f + ".qml")
    assert(num(v, /SearchPill\s*\{[\s\S]*?Layout\.preferredHeight:\s*(\d+|ReaderType\.\w+)/, f + " search height") === 40, f + ": search pill is 40 tall")
    assert(num(v, /ReaderChip\s*\{[\s\S]*?Layout\.preferredHeight:\s*(\d+|ReaderType\.\w+)\s*\n\s*icon:\s*"tune"/, f + " filters height") === 40, f + ": Filters chip is as tall as the search pill")
}
console.log("reader header keys: all checks passed")

// The screens under the header: one gutter, readable chapter stamps, no second circled x.
const views = ["BrowseView", "LibraryView", "DetailView", "InfoPanel"].map(n => [n, read("modules/sekai/readers/manga/" + n + ".qml")])
for (const [n, v] of views)
    assert(!/leftMargin:\s*14;\s*rightMargin:\s*(14|16|18)\b/.test(v), n + ": toolbars and sheets use the 16 px gutter on both sides")
const lib = views[1][1], det = views[2][1], info = views[3][1]
// the table: the rows sit in the gutter, the column titles 8 px further in (the row's own padding)
assert(/leftMargin:\s*16;\s*rightMargin:\s*16;\s*topMargin:\s*3;\s*bottomMargin:\s*3/.test(lib) && /anchors \{ fill: parent; leftMargin: 24; rightMargin: 24 \}/.test(lib), "the list rows and their column titles line up")
// the chapter stamp has one width and an ink that shows on its dark fill
const badge = det.match(/ReaderBadge\s*\{\s*id:\s*chapterBadge[\s\S]*?\n\s*\}/)
assert(badge && /Layout\.preferredWidth:\s*Math\.max\(\d+,\s*chapterBadge\.implicitWidth\)/.test(badge[0]), "chapter stamps share one width")
assert(badge && /ink:\s*isLastRead \? Theme\.colBorder : Theme\.ink/.test(badge[0]), "the chapter stamp's ink is readable on its fill")
const stampW = parseInt(badge[0].match(/Math\.max\((\d+),/)[1])
assert(new RegExp("leftMargin:\\s*" + (16 + stampW + 14) + ";\\s*rightMargin:\\s*16").test(det), "the divider between chapters starts under the titles")
// the keys beside the chapter filter are as tall as it is
assert(/id:\s*moreKey\s*\n\s*Layout\.preferredHeight:\s*(40|ReaderType\.hField)/.test(det) && /ReaderKey\s*\{\s*Layout\.preferredHeight:\s*(40|ReaderType\.hField)\s*\n\s*icon:\s*detailView\._sortAscending/.test(det), "the chapter keys are 40 tall like the filter")
// the Info sheet collapses with an arrow: an x is the window's close key
assert(/ReaderKey\s*\{\s*icon:\s*"expand_less"\s*\n\s*onClicked:\s*root\.close\(\)/.test(info), "the Info sheet's own key is a collapse arrow")
assert(!/ReaderKey\s*\{\s*icon:\s*"close"/.test(info), "no second circled x on the Info sheet")
console.log("reader screens: all checks passed")

// ── Design pass: one scale, one volume, one row style ───────────────────────────────────────
const badgeSrc = read("modules/sekai/readers/ReaderBadge.qml")
const chipSrc = read("modules/sekai/readers/ReaderChip.qml")
const browse = views[0][1]
// the scale: 24 stamp, 32 chip, 40 field / key, 48 row, nothing under 11
assert(tok("ReaderType.hBadge") === 24 && tok("ReaderType.hChip") === 32 && tok("ReaderType.hField") === 40 && tok("ReaderType.hRow") === 48, "the height scale is 24 / 32 / 40 / 48")
assert(/implicitHeight:\s*ReaderType\.hBadge/.test(badgeSrc) && /implicitHeight:\s*ReaderType\.hChip/.test(chipSrc), "stamps and chips take their height from the scale")
assert(/ReaderType\.sizeCaption/.test(badgeSrc) && tok("ReaderType.sizeCaption") === 11, "stamp text is 11 px, not 9")
for (const [n, v] of views.concat([["ReaderBadge", badgeSrc], ["ReaderChip", chipSrc]]))
    assert(!/font\.pixelSize:\s*(9|10)\b/.test(v), n + ": no text under 11 px")
// colour: solid accent is for a selection or the one primary action; information stamps are tonal
assert(/property bool tonal/.test(badgeSrc), "stamps have a tonal look")
assert(/text:\s*"TRACKED"\s*\n\s*tonal:\s*true/.test(det), "the TRACKED stamp is tonal")
assert(/tonal:\s*true\s*\n\s*text:\s*\{[\s\S]{0,260}LAST READ/.test(det), "the LAST READ stamp is tonal")
assert(!/ReaderKey\s*\{\s*Layout\.preferredHeight:\s*(40|ReaderType\.hField)\s*\n\s*lit:\s*true/.test(det), "the sort key is not lit (an order is not a selection)")
assert(!/lit:\s*Manga\.trackInfo !== null && Manga\.trackInfo\.entry !== null/.test(det), "the AniList chip is not lit")
assert(/fill:\s*ReaderType\.tagFill/.test(browse), "Browse's type tag is a dark tag, not a second accent stamp")
// the header keys draw a bare minus and x (the icon set's own come in a circle)
const hkSrc = read("modules/sekai/readers/HeaderKey.qml")
assert(/root\.icon === "remove"/.test(hkSrc) && /root\.icon === "close"/.test(hkSrc) && /rotation:\s*45/.test(hkSrc), "the window keys draw their own glyphs")
// one list language: the Library's rows are flat with a hairline, like the chapter list
assert(!/radius:\s*12\s*\n\s*color:\s*rowArea\.containsMouse \? Theme\.surfaceTint : Theme\.surfaceHover/.test(lib), "Library rows are not boxed")
assert(/Colors\.outline_variant; opacity: 0\.25/.test(lib), "Library rows have a hairline between them")
assert((det.match(/ReaderType\.hRow/g) || []).length >= 2 && !/height:\s*58\b[^\n]*\n[^\n]*\n\s*readonly property var _libEntry/.test(det), "chapter rows are 48")
// numbers line up on their last digit, and an empty cell is a dash
assert((lib.match(/horizontalAlignment:\s*Text\.AlignRight/g) || []).length >= 3 && /\\u2014/.test(lib), "Library numbers are right-aligned and empty cells are a dash")
// chapter rows do not write the number twice; the source line is part of the count row; Info has no second title
assert(/_hasTitle/.test(det) && /_sourceCaption/.test(det), "a title that repeats the stamp is not written out; the source is a caption")
assert(!/Layout\.preferredHeight:\s*visible \? 44 : 0/.test(det), "the source line is not a band of its own")
assert(!/root\.m \? root\.m\.title/.test(info), "the Info sheet does not repeat the title")
assert(/ReaderChip\s*\{[\s\S]*?"link"[\s\S]*?ReaderKey\s*\{\s*icon:\s*"expand_less"/.test(info), "the Info collapse key is at the right end")
console.log("reader design pass: all checks passed")
