// The lyrics widget is wired into the shell the way every desktop widget is, and the
// pieces agree with each other. Quickshell can't run here, so the rules are read from
// source. Run: node lyrics_source_test.js
const fs = require("fs"), assert = require("assert"), path = require("path")
const read = f => fs.readFileSync(path.join(__dirname, "..", "..", f), "utf8")
const W = read("modules/sekai/desktopWidgets/LyricsWidget.qml")
const Ln = read("modules/sekai/desktopWidgets/LyricsLine.qml")
const Wd = read("modules/sekai/desktopWidgets/LyricsWord.qml")
const S = read("services/LyricsService.qml")
const shell = read("shell.qml")
const em = read("services/EditMode.qml")

// ---- transparent: nothing is drawn behind the words ----
assert.ok(/color: "transparent"/.test(W), "the window is transparent")
assert.ok(!/Pill\b|Rectangle\s*\{[^}]*fillColor/.test(W), "no housing / card behind the lyrics")
assert.ok(!/\bRectangle\b/.test(W), "the widget draws no rectangle at all")

// ---- the window follows the other desktop widgets ----
assert.ok(/WlrLayershell\.namespace: "sekaipop-lyrics"/.test(W))
assert.ok(/WlrLayershell\.keyboardFocus: WlrKeyboardFocus\.None/.test(W), "it never takes the keyboard")
assert.ok(/FocusGate\s*\{[^}]*widgetId: "lyrics"/.test(W), "Focus Mode hides it")
assert.ok(/mask: Region/.test(W) && /EditMode\.desktopDragAllowed \|\| EditMode\.active \|\| chrome\.selected/.test(W), "clicks fall through while Lock all is on")
assert.ok(/EditChrome\s*\{[^}]*widgetId: "lyrics"/.test(W) && /EditPreview\s*\{[^}]*widgetId: "lyrics"/.test(W), "Edit Desktop knows it")
assert.ok(/visible: LyricsService\.loaded && \(win\.live \|\| EditMode\.active\)/.test(W), "not mapped while it is off")
assert.ok(/readonly property bool want: win\.switchedOn && gate\.show && \(win\.present \|\| win\.demo\)/.test(W), "it goes away when nothing is playing")

// ---- the time ----
assert.ok(/LM\.observe\(win\.clk, polled/.test(W) && /p\.positionChanged\(\)/.test(W), "the position is polled and a clock runs in between")
assert.ok(!/LM\.retune/.test(W), "the old averaging clock is gone")
assert.ok(/LM\.clockReset\(0, Date\.now\(\)\)/.test(W) && /LM\.clockReset\(LM\.estimate\(win\.clk, now, !win\.playing\), now\)/.test(W), "a new song and a pause / resume reset the clock's history")
assert.ok(/interval: 250/.test(W))
assert.ok(/FrameAnimation\s*\{\s*running: win\.live && \(win\.demo \|\| win\.playing\)/.test(W), "frames only run while something moves")
assert.ok(/LyricsService\.syncTotal \/ 1000/.test(W), "the nudges (the player's and this song's) are applied")
assert.ok(/LM\.pollTrust\(/.test(W), "a position that does not move is not trusted")
assert.ok(/readonly property string identSig/.test(W) && /onIdentSigChanged/.test(W) && !/onTrackSigChanged: \{\s*win\.clk/.test(W), "the clock restarts for a new song, not when the length arrives")
assert.ok(/onPlayingChanged:[\s\S]*?LM\.estimate\(win\.clk, now, !win\.playing\)/.test(W), "pause / resume keeps the clock's place even without a position from the player")
assert.ok(/icon: "double_alt_arrow_left"\s*tipBelow: true\s*tip: "later"[\s\S]*?LyricsService\.nudge\(-100\)/.test(W) && /icon: "double_alt_arrow_right"\s*tipBelow: true\s*tip: "earlier"[\s\S]*?LyricsService\.nudge\(100\)/.test(W) && /tip: "sources"/.test(W) && /LyricsService\.setTrackOffset\(0\)/.test(W), "the sync keys: later, this song's nudge, earlier (icon keys with a hover tag), sources")
assert.ok(W.indexOf('tip: "later"') < W.indexOf('tip: "earlier"'), "later sits left of earlier")
assert.ok(/keysOn: hover\.hovered && !EditMode\.active && cardMask\.grab/.test(W), "the keys show when pointed at, not while editing")
assert.ok(/versionDiff/.test(W), "the tag says when the lyrics are for another cut")
assert.ok(/LM\.cursor\(win\.lines, win\.clockT, /.test(W) && /d: slot\.index - win\.cursorV/.test(W), "the lines follow the cursor")
assert.ok(/active: Math\.abs\(slot\.index - win\.base\) <= 2/.test(W), "only the lines near the middle are built")

// ---- the line ----
assert.ok(/LM\.takeover\(line\.d, line\.held\)/.test(Ln) && /LM\.tokens\(line\.text\)/.test(Ln) && /LM\.hop\(/.test(Ln) && /LM\.hit\(/.test(Ln))
assert.ok(/DiamondDot/.test(Ln) && /Burst/.test(Ln), "the marker and the burst")
assert.ok(/litOn: !line\.still && \(line\.index === line\.curIndex \|\| line\.index === line\.curIndex - 1 \|\| line\.carried\)/.test(Ln), "the line on, the one before it and one that is still being sung keep the sung layer, no others")
assert.ok(!/localStorage/.test(Ln + W + S))
// ---- timing and ad libs ----
assert.ok(/LM\.songRate\(win\.lines\)/.test(W) && /LM\.sungSpan\(l\.text, room, win\.rate, known\)/.test(W), "a line is as long as the song's own rate says, or as its end stamp says")
assert.ok(/marks: .*\.marks/.test(W) && /bgText: .*\.bg\.text/.test(W) && /bgStart: .*\.bg\.t/.test(W), "the line is given its word timing and the voice that sings along")
assert.ok(/LM\.spansFor\(line\.toks, /.test(Ln) && /LM\.mainIndexes\(line\.toks\)/.test(Ln), "word times from the file when it has them; the marker over the tune's words")
assert.ok(/onKmChanged/.test(Ln) && !/onKChanged/.test(Ln) && /line\.mainIdx\[line\.km\]/.test(Ln), "the puff follows the marker, not the ad libs")
assert.ok(/modelData\.adlib === true/.test(Ln) && /litColor: cell\.ad \? Theme\.accentMint/.test(Ln), "ad libs have their own look")
assert.ok(/LM\.tokens\(line\.bgText\)/.test(Ln) && /bgRow/.test(Ln), "a voice that sings along is a small row")
assert.ok(/property bool debug: false/.test(S) && /LyricsService\.debug/.test(W) && !/debug/.test(S.slice(S.indexOf("function snapshot"), S.indexOf("function restore"))), "the debug line is not saved")

// ---- fast entries ----
assert.ok(/LM\.foldEchoes\(LM\.parseLrc\(got\.synced/.test(S), "an echo that comes in during a line is folded into it as the lyrics are loaded")
assert.ok(/function bgEndOf/.test(W) && /bgEnd: win\.bgEndOf\(slot\.index\)/.test(W) && /property real bgEnd/.test(Ln), "the voice that sings along can outlast its line")
// a line that is leaving while it is still being sung is HELD (above the new line, strong, still singing),
// then lets go: the old fixed-size "busy" hold is gone, and the pieces agree with each other
assert.ok(!/\bbusy\b/.test(Ln), "the old fixed hold is gone")
assert.ok(/LM\.hold\(line\.t, line\.lineEnd, line\.rush\)/.test(Ln) && /LM\.takeover\(line\.d, line\.held\)/.test(Ln), "a line is held while it is still being sung, then lets go")
assert.ok(/LM\.hold\(line\.t, line\.prevEnd, line\.prevRush\)/.test(Ln) && /archK: .*line\.heldAbove/.test(Ln), "the new line's marker hops lower while a line is held above it")
assert.ok(/LM\.landing\(line\.t - line\.lineStart, line\.entryRush\)/.test(Ln) && /1 \+ 0\.06 \* line\.land/.test(Ln), "the line that took over lands with a swell")
assert.ok(/readonly property bool carried:.*line\.index < line\.curIndex.*line\.t < line\.lineEnd/.test(Ln) && /readonly property bool singing: line\.isCur \|\| line\.carried/.test(Ln), "a line that was taken over is still singing: fill, marker and puff go on")
assert.ok(/line\.singing && line\.playing && line\.km >= 0/.test(Ln) && /line\.singing && line\.playing\) \? LM\.hit/.test(Ln), "the diamonds and the squash follow a line that is still sung")
assert.ok(/onDoneChanged/.test(Ln) && /signoff\.fire\(\)/.test(Ln) && /line\.t - line\.lineEnd < 0\.35/.test(Ln), "the sign-off when it ends, not when a seek jumps past it")
assert.ok(/readonly property int kmAny: LM\.wordAt\(line\.mainSp, line\.t\)/.test(Ln) && /hereM: Math\.max\(0, line\.kmAny\)/.test(Ln), "the marker that is shrinking away stays on its word")
assert.ok(/function rushAfter\(i\)/.test(W) && /LM\.leaveAt\(l\.t, win\.lines\[i \+ 1\]\.t, win\.lead\)/.test(W) && /rush: win\.rushAfter\(slot\.index\)/.test(W) && /prevRush: win\.rushAfter\(slot\.index - 1\)/.test(W) && /prevEnd: slot\.index > 0 \? win\.endOf\(slot\.index - 1\) : 0/.test(W), "the widget tells each line how much it is held and how much the one before it is")
assert.ok(/function takeAfter\(i\)/.test(W) && /LM\.cursor\(win\.lines, win\.clockT, win\.lead, win\.nextRush\)/.test(W) && /nextRush: win\.takeAfter\(win\.curIndex\)/.test(W), "the stack climbs a little longer for a takeover")
assert.ok(/l\.text === ""/.test(W) && /win\.lines\[i\]\.text === ""/.test(W), "a gap in the singing is never held or taken over")

// ---- the word ----
assert.ok(/model: 8/.test(Wd) && /model: 4/.test(Wd), "outline and shadow")
assert.ok(/Theme\.accentCyan/.test(Wd), "the sung colour comes from the theme")

// ---- the service ----
assert.ok(/lrclib\.net\/api/.test(S) && /Lrclib-Client/.test(S))
// fetched with curl in a Process, like the rest of the shell (not XMLHttpRequest)
assert.ok(/"curl", "-sS", "-m", "10"/.test(S) && !/XMLHttpRequest/.test(S), "curl, as the weather does")
assert.ok(/interval: 12000/.test(S), "a call that hangs is given up")
assert.ok(/ctx\.answered = true/.test(S) && /status = "offline"/.test(S), "no answer at all is offline, and is not remembered as a miss")
assert.ok(/lyrics-cache\.sh/.test(S) && /lyrics-state\.sh/.test(S))
for (const f of ["scripts/state/lyrics-cache.sh", "scripts/state/lyrics-state.sh"])
    assert.ok(fs.existsSync(path.join(__dirname, "..", "..", f)), f + " exists")
assert.ok(/root\.shown = s\.shown === true/.test(S), "off until added")
assert.ok(/readonly property int syncTotal: root\.syncMs \+ root\.trackOffsetMs/.test(S), "the player-wide and the song's nudge add up")
assert.ok(/function setTrackOffset/.test(S) && /offsets: root\.offsets/.test(S), "a song's nudge is remembered")
assert.ok(/root\.versionDiff = /.test(S) && /got\.duration/.test(S), "the length the lyrics were made for is kept")
// only the artist, title, album and length go out
const urls = [...S.matchAll(/root\.base \+ "\/(get|search)\?/g)]
assert.strictEqual(urls.length, 3, "an exact lookup and two searches")
assert.ok(!/ctx\.(url|path)\b[^;]*encodeURIComponent|encodeURIComponent\(ctx\.url/.test(S))
assert.ok(!/ctx\.url\s*\)?\s*\+|encodeURIComponent\(ctx\.url/.test(S), "the file path is never sent")
assert.ok(/Date\.now\(\) - missed < 600000/.test(S), "a miss is not asked again for ten minutes")

// ---- wired in ----
assert.ok(/id: lyricsGate/.test(shell) && /LyricsWidget \{\}/.test(shell) && /target: "lyrics"/.test(shell), "shell.qml: gate, loader, ipc")
for (const fn of ["toggle", "show", "hide", "nudge", "nudgeAll", "refresh", "debug", "resetPosition"])
    assert.ok(new RegExp('target: "lyrics"[\\s\\S]*?function ' + fn + "\\(").test(shell), "ipc lyrics " + fn)
assert.ok(/id: "lyrics", title: "Lyrics"/.test(em) && /LyricsService\.setShown\(true\)/.test(em) && /LyricsService\.setShown\(false\)/.test(em))
assert.ok(/lyrics: 9/.test(read("modules/common/functions/FocusMath.js")))
assert.ok(/service: LyricsService, skip: \["syncMs", "offsets"\]/.test(read("services/PresetWidgets.qml")))
for (const f of ["modules/sekai/settings/SettingsPageDesktop.qml", "modules/sekai/settings/SettingsPageQuick.qml"])
    assert.ok(/LyricsService\.setShown/.test(read(f)), f + " has the switch")

console.log("lyrics_source_test: all checks passed")

{
    const svc = fs.readFileSync(path.join(__dirname, "../../services/LyricsService.qml"), "utf8")
    for (const id of ["lyricsplus", "netease", "lrclib", "qq", "kugou"])
        assert.ok(new RegExp('\\{ id: "' + id + '"').test(svc), "provider " + id)
    assert.ok(/function gather/.test(svc) && /function finalize/.test(svc) && /LM\.chooseLyrics/.test(svc), "all are asked and the best chosen")
    assert.ok(/property string preferred: "auto"/.test(svc) && /source: root\.preferred/.test(svc), "the chosen provider is remembered")
    assert.ok(!/fromNet|upgradeWords/.test(svc), "the one-provider flow is gone")
    const sh = fs.readFileSync(path.join(__dirname, "../../shell.qml"), "utf8")
    assert.ok(/function source\(id: string\)/.test(sh) && /function sources\(\): string/.test(sh), "ipc lyrics source / sources")
}

{
    const P = fs.readFileSync(path.join(__dirname, "../../modules/sekai/desktopWidgets/LyricsSources.qml"), "utf8")
    const svc = fs.readFileSync(path.join(__dirname, "../../services/LyricsService.qml"), "utf8")
    const sh = fs.readFileSync(path.join(__dirname, "../../shell.qml"), "utf8")
    const W = fs.readFileSync(path.join(__dirname, "../../modules/sekai/desktopWidgets/LyricsWidget.qml"), "utf8")
    assert.ok(/WlrLayershell\.layer: WlrLayer\.Overlay/.test(P) && /visible: LyricsService\.pickerOpen \|\| card\.popProgress > 0\.001/.test(P), "an overlay that exists only while open (and while the card pops away)")
    assert.ok(/transformOrigin: Item\.Center/.test(P) && !/origin\.y: 0/.test(P), "the card pops up out of its middle, not an edge")
    assert.ok(/function away\(\)/.test(P) && /awayAnim/.test(P), "and goes back into it")
    assert.ok(/onPressed: LyricsService\.closePicker\(\)/.test(P) && /Keys\.onEscapePressed/.test(P), "a click elsewhere or Esc closes it")
    assert.ok(/model: LyricsService\.providers/.test(P), "one row per provider")
    assert.ok(/setPreferred\("auto"\)/.test(P) && /setPreferred\(line\.modelData\.id\)/.test(P), "Auto and each provider can be picked")
    for (const t of ["WORD BY WORD", "SYNCED", "Not found", "Unreachable", "Try again"])
        assert.ok(P.indexOf(t) >= 0, "row says " + t)
    assert.ok(/LyricsService\.sourceStates\[/.test(P), "each row shows what that provider found")
    assert.ok(/function openPicker/.test(svc) && /function togglePicker/.test(svc) && /property string sourceKind/.test(svc))
    assert.ok(/LyricsSources \{\}/.test(sh) && /active: LyricsService\.pickerOpen \|\| LyricsService\.pickerLinger/.test(sh), "built in shell.qml only while open (and while it pops away)")
    assert.ok(/function picker\(\): void/.test(sh), "ipc lyrics picker")
    assert.ok(/label: "sources"/.test(W) && /togglePicker/.test(W), "a key under the lyrics opens it")
}

// ---- Boidu first, then the rest in the order they were asked for; changeable from Settings ----
{
    const svc = fs.readFileSync(path.join(__dirname, "../../services/LyricsService.qml"), "utf8")
    const sets = fs.readFileSync(path.join(__dirname, "../../modules/sekai/settings/SettingsPageDesktop.qml"), "utf8")
    const P = fs.readFileSync(path.join(__dirname, "../../modules/sekai/desktopWidgets/LyricsSources.qml"), "utf8")
    const list = svc.slice(svc.indexOf("readonly property var providers: ["), svc.indexOf("readonly property var providerIds"))
    const ids = [...list.matchAll(/\{ id: "(\w+)"/g)].map(m => m[1])
    assert.deepStrictEqual(ids, ["boidu", "lyricsplus", "lrclib", "youtubemusic", "simpmusic", "netease", "qq", "kugou"], "the order the providers are liked in")
    for (const [id, fn] of [["boidu", "pBoidu"], ["youtubemusic", "pYoutubeMusic"], ["simpmusic", "pSimpmusic"], ["lrclib", "pLrclib"], ["netease", "pNetease"], ["qq", "pQq"], ["kugou", "pKugou"], ["lyricsplus", "pLyricsplus"]]) {
        assert.ok(new RegExp('id === "' + id + '"\\)\\s*root\\.' + fn + "\\(ctx, cb\\)").test(svc), id + " is asked through " + fn)
        assert.ok(new RegExp("function " + fn + "\\(ctx, cb\\)").test(svc), fn + " exists")
    }
    assert.ok(/api\.betterlyrics\.org/.test(svc) && /lyrics-api\.boidu\.dev/.test(svc), "Boidu: the new address, then the old one")
    assert.ok(/"&a=" \+ encodeURIComponent\(c\.artist\)/.test(svc) && /"&al=" \+/.test(svc) && /"&d=" \+ Math\.round\(ctx\.length\)/.test(svc), "Boidu is sent the song, the artist, the album and the length")
    assert.ok(/LM\.ttmlToLrc\(o\.ttml\)/.test(svc) && /trusted:/.test(svc) && /trusted: res\.trusted === true/.test(svc), "its TTML is read, and a sure match is trusted")
    assert.ok(/api-lyrics\.simpmusic\.org/.test(svc) && /LM\.simpmusicPick\(/.test(svc) && /LM\.videoIdOf\(ctx\.url\)/.test(svc), "SimpMusic by the video id")
    assert.ok(/WEB_REMIX/.test(svc) && /ANDROID_MUSIC/.test(svc) && /LM\.ytmLyricsBrowseId\(j\)/.test(svc) && /LM\.ytmTimedLyrics\(j2\)/.test(svc), "YouTube Music: /next -> lyrics tab -> /browse")
    assert.ok(/function post\(url, body, cb, extra\)/.test(svc) && /"--data-binary", body/.test(svc), "the POST helper")
    assert.ok(!/encodeURIComponent\(ctx\.url\)|"videoId": ctx\.url/.test(svc), "the track's address itself is never sent, only a YouTube video id out of it")
    // the choice: every spelling of a name, from the picker, Settings and ipc
    assert.ok(/function providerId\(x\)/.test(svc) && /neteasecloudmusic: "netease"/.test(svc) && /qqmusic: "qq"/.test(svc) && /const v = root\.providerId\(id\)/.test(svc), "ipc lyrics source takes the names as they were written")
    assert.ok(/SettingChoice\s*\{\s*label: "Lyrics source"/.test(sets) && /LyricsService\.setPreferred\(id\)/.test(sets) && /LyricsService\.providers\.map/.test(sets) && /current: LyricsService\.preferred/.test(sets), "Settings -> Desktop has the source chooser")
    assert.ok(/LyricsService\.setWords\(!LyricsService\.wordsOn\)/.test(sets), "and the word-by-word switch")
    assert.ok(/note: line\.modelData\.hint/.test(P), "the picker shows each provider's hint")
    // old cache entries kept as line-synced are asked once more
    assert.ok(/readonly property int cacheRev: 2/.test(svc) && /rev: root\.cacheRev/.test(svc) && /\(got\.rev \|\| 0\) < root\.cacheRev/.test(svc), "an older line-synced cache entry is asked again once")
    console.log("lyrics sources (boidu first): ok")
}
