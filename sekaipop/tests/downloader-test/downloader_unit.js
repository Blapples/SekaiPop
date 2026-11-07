// node tests/downloader-test/downloader_unit.js   (run from the sekaipop folder)
//
// The desktop Downloader (services/DownloaderService.qml, modules/sekai/desktopWidgets/DownloaderWidget.qml,
// DownloaderTile.qml, scripts/downloader/download.sh). All of its logic is in
// modules/common/functions/DownloadMath.js, which this runs on its own; Quickshell can't be used here,
// so the QML is only checked for wiring.
//   1. links: the first link in some text, the site word
//   2. options: clamping, cycling, which engine does the work
//   3. what the script says (progress, title, file, error)
//   4. the queue: new jobs, patching, trimming, remembering
//   5. the script itself (a fake yt-dlp and a fake curl in front of PATH)
//   6. the QML is wired to it (service, widget, registry, edit mode, settings, ipc, icons, deps)
const fs = require("fs"), assert = require("assert"), cp = require("child_process"), os = require("os"), path = require("path")
const locate = require("../lib/locate")
const read = f => fs.readFileSync(locate(f), "utf8")
const src = read("modules/common/functions/DownloadMath.js").replace(".pragma library", "")
const D = {}
new Function("D", src + ";Object.assign(D,{firstUrl,isUrl,hostOf,siteWord,clampMode,clampQuality,clampAudio,clampEngine,nextIn,qualityText,modeText,modeIcon,pickEngine,missingText,engineText,clampNames,clampBrowser,cleanLang,firstChoosing,typeIcon,addItem,maskOf,toggleMask,countOn,chosenItems,itemsText,wantsLogin,shortReason,percentOf,cleanText,parseLine,fileName,shorten,newJob,nextQueued,indexOfId,isLive,stats,patch,trimJobs,remember,recall,nextId,MODES,QUALITIES,AUDIO_FORMATS,ENGINES,NAMES,BROWSERS,MAX_ITEMS,KEEP_DONE,KEEP_JOBS});")(D)
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---- 1. links ----
eq(D.firstUrl("https://youtu.be/abc123"), "https://youtu.be/abc123")
eq(D.firstUrl("  look at this https://www.youtube.com/watch?v=abc&t=5s  lol"), "https://www.youtube.com/watch?v=abc&t=5s", "a link inside a sentence")
eq(D.firstUrl("(see https://example.org/a/b)."), "https://example.org/a/b", "brackets and a full stop after it go")
eq(D.firstUrl("https://en.wikipedia.org/wiki/Foo_(bar)"), "https://en.wikipedia.org/wiki/Foo_(bar)", "a bracket that belongs to the link stays")
eq(D.firstUrl("https://example.org/a, and https://other.org/b"), "https://example.org/a", "the first one")
eq(D.firstUrl("no link here"), "")
eq(D.firstUrl(""), "")
eq(D.firstUrl(undefined), "")
eq(D.firstUrl("ftp://example.org/x"), "", "only http(s)")
eq(D.firstUrl("https://localhost:8080/x.mp4"), "https://localhost:8080/x.mp4")
eq(D.firstUrl("https://nonsense"), "", "a word with no dot is not a site")
ok(D.isUrl("https://a.org/x") && !D.isUrl("a.org/x"))
eq(D.hostOf("https://www.youtube.com/watch?v=1"), "youtube.com")
eq(D.hostOf("https://m.youtube.com/watch"), "youtube.com")
eq(D.hostOf("https://Music.YouTube.com:443/x"), "music.youtube.com")
eq(D.hostOf("nothing"), "")
eq(D.siteWord("https://www.youtube.com/watch?v=1"), "YOUTUBE")
eq(D.siteWord("https://music.youtube.com/x"), "YOUTUBE")
eq(D.siteWord("https://www.bbc.co.uk/x"), "BBC")
eq(D.siteWord("https://x.com/a/status/1"), "X")
eq(D.siteWord("junk"), "")

// ---- 2. options ----
eq(D.clampMode("audio"), "audio"); eq(D.clampMode("nonsense"), "video"); eq(D.clampMode(undefined), "video")
eq(D.clampQuality("720"), "720"); eq(D.clampQuality(720), "720", "a number works"); eq(D.clampQuality("9999"), "1080")
eq(D.clampAudio("opus"), "opus"); eq(D.clampAudio("aac?"), "mp3")
eq(D.clampEngine("cobalt"), "cobalt"); eq(D.clampEngine("x"), "auto")
eq(D.nextIn(D.MODES, "video"), "audio"); eq(D.nextIn(D.MODES, "mute"), "video", "wraps round"); eq(D.nextIn(D.MODES, "zzz"), "video")
eq(D.nextIn(D.QUALITIES, "max"), "1080")
eq(D.qualityText("max"), "BEST"); eq(D.qualityText("720"), "720P")
eq(D.modeText("audio"), "AUDIO"); eq(D.modeText("mute"), "MUTE"); eq(D.modeText("video"), "VIDEO")
eq(D.modeIcon("audio"), "music_note")
eq(D.pickEngine("auto", true, "", false), "auto", "auto: something can run")
eq(D.pickEngine("auto", false, "https://c.example", false), "auto", "auto: only cobalt")
eq(D.pickEngine("auto", false, "", true), "auto", "auto: only gallery-dl")
eq(D.pickEngine("auto", false, "  ", false), "", "auto: nothing at all")
eq(D.pickEngine("cobalt", true, "", true), "", "cobalt asked, no instance")
eq(D.pickEngine("cobalt", false, "https://c.example", false), "cobalt")
eq(D.pickEngine("ytdlp", false, "https://c.example", true), "", "yt-dlp asked, not installed")
eq(D.pickEngine("gallerydl", true, "", true), "gallerydl"); eq(D.pickEngine("gallerydl", true, "x", false), "", "gallery-dl asked, not installed")
ok(/yt-dlp/.test(D.missingText("auto", false, "", false)) && /gallery-dl/.test(D.missingText("auto", false, "", false)))
ok(/gallery-dl/.test(D.missingText("gallerydl", true, "", false)))
ok(/cobalt/i.test(D.missingText("cobalt", true, "", true)))
eq(D.missingText("auto", true, "", false), ""); eq(D.missingText("auto", false, "", true), "")
eq(D.engineText("ytdlp"), "YT-DLP"); eq(D.engineText("gallerydl"), "GALLERY-DL"); eq(D.engineText("cobalt"), "COBALT"); eq(D.engineText(""), "")
eq(D.clampNames("pretty"), "pretty"); eq(D.clampNames("zzz"), "basic")
eq(D.clampBrowser("firefox"), "firefox"); eq(D.clampBrowser("netscape"), ""); eq(D.clampBrowser(""), "")
eq(D.cleanLang("en"), "en"); eq(D.cleanLang(" pt-BR "), "pt-BR"); eq(D.cleanLang("english"), ""); eq(D.cleanLang("en; rm -rf"), "", "nothing odd gets through"); eq(D.cleanLang(undefined), "")
eq(D.ENGINES, ["auto", "ytdlp", "gallerydl", "cobalt"])

eq(D.shortReason("Nothing copied: copy a link first"), "NO LINK"); eq(D.shortReason("That isn't a link"), "NOT A LINK"); eq(D.shortReason("yt-dlp is not installed"), "SET UP FIRST")

// ---- 3. what the script says ----
eq(D.percentOf("  45.3%"), 45.3); eq(D.percentOf("100%"), 100); eq(D.percentOf("NA"), -1); eq(D.percentOf(""), -1); eq(D.percentOf("250%"), 100, "never over 100")
eq(D.cleanText("Unknown B/s"), ""); eq(D.cleanText("NA"), ""); eq(D.cleanText(" 12.3MiB/s "), "12.3MiB/s"); eq(D.cleanText(undefined), "")
eq(D.parseLine("SEKAI|title|My Test Clip"), { kind: "title", text: "My Test Clip" })
eq(D.parseLine("SEKAI|title|a | b"), { kind: "title", text: "a | b" }, "a bar in a title stays")
eq(D.parseLine("SEKAI|prog|  35.1%|  11.96MiB/s|00:00"), { kind: "prog", pct: 35.1, speed: "11.96MiB/s", eta: "00:00" })
eq(D.parseLine("SEKAI|prog|  2.3%| Unknown B/s|Unknown"), { kind: "prog", pct: 2.3, speed: "", eta: "" })
eq(D.parseLine("SEKAI|prog|||"), { kind: "prog", pct: -1, speed: "", eta: "" }, "asking the instance: no percent yet")
eq(D.parseLine("SEKAI|file|/tmp/a b.mp4"), { kind: "file", path: "/tmp/a b.mp4" })
eq(D.parseLine("SEKAI|err|boom"), { kind: "err", text: "boom" })
eq(D.parseLine("SEKAI|done"), { kind: "done" })
eq(D.parseLine("SEKAI|done\r"), { kind: "done" }, "a stray carriage return")
eq(D.parseLine("SEKAI|engine|gallerydl"), { kind: "engine", name: "gallerydl" })
eq(D.parseLine("SEKAI|choose|3"), { kind: "choose", count: 3 })
eq(D.parseLine("SEKAI|item|video\thttps://a/b.mp4?x=1|2\thttps://a/t.jpg"), { kind: "item", type: "video", url: "https://a/b.mp4?x=1|2", thumb: "https://a/t.jpg" }, "a bar in an address stays")
eq(D.parseLine("SEKAI|item|weird\thttps://a/b"), { kind: "item", type: "photo", url: "https://a/b", thumb: "" }, "an unknown type is a photo")
eq(D.parseLine("SEKAI|item|photo"), null, "an item with no address is nothing")
eq(D.parseLine("[download] 10%"), null, "anything else is not ours")
eq(D.parseLine(""), null); eq(D.parseLine(undefined), null); eq(D.parseLine("SEKAI|what|x"), null)
eq(D.fileName("/a/b/c d.mp4"), "c d.mp4"); eq(D.fileName("x.mp3"), "x.mp3"); eq(D.fileName(""), "")
eq(D.shorten("short", 20), "short")
const sh = D.shorten("A really quite long video title.mp4", 20)
ok(sh.length === 20 && sh.endsWith("le.mp4") && sh.includes("\u2026"), "cut in the middle, the end stays: " + sh)

// ---- 4. the queue ----
const opts = { mode: "audio", quality: "720", engine: "ytdlp" }
const j1 = D.newJob(1, "https://www.youtube.com/watch?v=1", opts, 1000)
eq([j1.status, j1.host, j1.mode, j1.quality, j1.pct], ["queued", "youtube.com", "audio", "720", -1])
eq(D.newJob(2, "https://a.org/x", { mode: "zzz", quality: "zzz", engine: "cobalt" }, 5).mode, "video", "bad options are clamped")
let jobs = [j1, D.newJob(2, "https://a.org/x", opts, 2000), D.newJob(3, "https://b.org/x", opts, 3000)]
eq(D.nextQueued(jobs), 0); eq(D.indexOfId(jobs, 3), 2); eq(D.indexOfId(jobs, 9), -1)
jobs = D.patch(jobs, 1, { status: "running", pct: 10 })
ok(jobs[0].status === "running" && jobs[0].pct === 10 && jobs[0].url === j1.url, "patched, the rest kept")
ok(j1.status === "queued", "the old job object is untouched (QML needs a new one to see a change)")
eq(D.nextQueued(jobs), 1, "the running one is skipped")
eq(D.patch(jobs, 99, { status: "done" }).length, 3, "an unknown id changes nothing")
jobs = D.patch(D.patch(jobs, 1, { status: "done", file: "/tmp/a.mp3" }), 2, { status: "failed", error: "x" })
eq(D.stats(jobs), { running: 0, queued: 1, choosing: 0, done: 1, failed: 1 })
ok(D.isLive(jobs[2]) && !D.isLive(jobs[0]))
eq(D.nextId(jobs), 4); eq(D.nextId([]), 1)
// choosing counts as live: it is never trimmed away or forgotten while it waits
const jc = Object.assign(D.newJob(9, "https://a.org/p", opts, 9), { status: "choosing", items: [{ type: "photo", url: "u1", thumb: "u1" }] })
ok(D.isLive(jc) && D.stats([jc]).choosing === 1, "a post waiting to be chosen from is live")
eq(D.remember([jc]), [], "and is not remembered")
eq(D.newJob(1, "https://a.org", opts, 1).items, []); eq(D.newJob(1, "https://a.org", opts, 1).fetch, [])

// ---- the picker ----
eq(D.firstChoosing([j1, jc]), 1); eq(D.firstChoosing([j1]), -1)
eq(D.typeIcon("video"), "movie"); eq(D.typeIcon("photo"), "image")
let its = []
its = D.addItem(its, { type: "photo", url: "u1", thumb: "t1" }); its = D.addItem(its, { type: "video", url: "u2", thumb: "" }); its = D.addItem(its, { type: "photo", url: "u1", thumb: "t1" })
eq(its.length, 2, "the same address twice is one item")
let many2 = []; for (let i = 0; i < 100; i++) many2 = D.addItem(many2, { type: "photo", url: "u" + i, thumb: "" })
eq(many2.length, D.MAX_ITEMS, "at most " + D.MAX_ITEMS + " items")
eq(D.maskOf(3, true), [true, true, true]); eq(D.maskOf(2, false), [false, false])
let mk = D.maskOf(3, true)
mk = D.toggleMask(mk, 1)
eq(mk, [true, false, true]); eq(D.countOn(mk), 2)
eq(D.toggleMask(mk, 9), mk, "an item that is not there changes nothing"); eq(D.toggleMask(mk, -1), mk)
eq(D.chosenItems([{ type: "photo", url: "a", thumb: "x" }, { type: "video", url: "b", thumb: "" }, { type: "photo", url: "c", thumb: "" }], mk), [{ type: "photo", url: "a" }, { type: "photo", url: "c" }], "only the ticked ones, without their pictures")
eq(D.itemsText([{ type: "photo", url: "a" }, { type: "video", url: "ytdl:b" }]), "photo\ta\nvideo\tytdl:b", "what the script reads")
eq(D.itemsText([]), "")
ok(D.wantsLogin("Login required to view this") && D.wantsLogin("This video is private") && !D.wantsLogin("Unable to download webpage") && !D.wantsLogin(""), "which failures a login would fix")
// trimming keeps the live ones whatever happens
let many = []
for (let i = 1; i <= 50; i++) many.push(Object.assign(D.newJob(i, "https://a.org/" + i, opts, i), { status: i === 3 ? "running" : "done", file: "/t/" + i }))
const tr = D.trimJobs(many)
ok(tr.length <= D.KEEP_JOBS + 1 && tr.some(j => j.id === 3) && tr[tr.length - 1].id === 50 && !tr.some(j => j.id === 1), "trimmed: oldest finished go, a live one stays")
// what is remembered
const rem = D.remember(many)
ok(rem.length === D.KEEP_DONE && rem[rem.length - 1].id === 50 && !rem.some(r => r.id === 3), "only finished ones with a file, the newest " + D.KEEP_DONE)
eq(D.remember([Object.assign(D.newJob(1, "https://a.org", opts, 1), { status: "done", file: "" })]), [], "done without a file is not remembered")
eq(D.remember([Object.assign(D.newJob(1, "https://a.org", opts, 1), { status: "failed" })]), [], "failed ones are not remembered")
const back = D.recall(JSON.parse(JSON.stringify(rem)))
ok(back.length === rem.length && back.every(b => b.status === "done" && b.pct === 100), "recalled as done jobs")
eq(D.recall("nonsense"), []); eq(D.recall([null, {}, { file: "x" }, { id: 1, file: "" }]), [], "junk is skipped")
eq(D.recall([{ id: 7, file: "/t/x.mp4" }])[0].title, "x.mp4", "a saved job with no title is called by its file")

// ---- 5. the script ----
const script = locate("scripts/downloader/download.sh")
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dltest-"))
const bin = path.join(tmp, "bin"); fs.mkdirSync(bin)
const out = path.join(tmp, "out")
const put = (name, body) => { fs.writeFileSync(path.join(bin, name), "#!/bin/sh\n" + body); fs.chmodSync(path.join(bin, name), 0o755) }
const run = (args, env) => cp.spawnSync("bash", [script, ...args], { encoding: "utf8", env: Object.assign({}, process.env, { PATH: bin + ":/usr/bin:/bin", HOME: tmp }, env || {}) })
const lines = r => r.stdout.split("\n").filter(Boolean)
const hasTool = c => cp.spawnSync("sh", ["-c", "command -v " + c]).status === 0
if (hasTool("bash") && hasTool("mktemp")) {
    // a fake yt-dlp that records how it was called, makes the file it was asked for, and talks like the real one
    put("yt-dlp", `echo "$@" > "${tmp}/ytargs"
case "$*" in
  *FAIL*) echo "ERROR: [generic] Unsupported URL: x" >&2; exit 1 ;;
esac
mkdir -p "${out}"; echo data > "${out}/Clip.mp4"
echo "SEKAI|title|Clip"; echo "SEKAI|prog|  50.0%|  1.0MiB/s|00:01"; echo "SEKAI|file|${out}/Clip.mp4"; exit 0`)
    put("ffmpeg", "exit 0")
    let r = run(["ytdlp", "video", "720", "mp3", out, "https://a.org/v"])
    eq(r.status, 0, "ytdlp ok: " + r.stderr)
    eq(lines(r).slice(-2), ["SEKAI|file|" + out + "/Clip.mp4", "SEKAI|done"], "a finished download ends with its file and done")
    let a = fs.readFileSync(path.join(tmp, "ytargs"), "utf8")
    ok(/--no-playlist/.test(a) && /height<=\?720/.test(a) && /--merge-output-format mp4\/mkv/.test(a) && /--paths /.test(a) && /-- https:\/\/a\.org\/v/.test(a), "video: one item, 720 at most, mp4 or mkv, the link after --: " + a)
    run(["ytdlp", "audio", "max", "opus", out, "https://a.org/v"])
    a = fs.readFileSync(path.join(tmp, "ytargs"), "utf8")
    ok(/-x --audio-format opus/.test(a) && !/merge-output/.test(a), "audio: extract as opus: " + a)
    run(["ytdlp", "audio", "max", "ogg", out, "https://a.org/v"])
    ok(/--audio-format vorbis/.test(fs.readFileSync(path.join(tmp, "ytargs"), "utf8")), "ogg is called vorbis by yt-dlp")
    run(["ytdlp", "mute", "max", "mp3", out, "https://a.org/v"])
    a = fs.readFileSync(path.join(tmp, "ytargs"), "utf8")
    ok(/-f bv\*\/b/.test(a) && !/ba\//.test(a) && !/-x /.test(a), "mute: video only: " + a)
    run(["ytdlp", "video", "max", "mp3", out, "https://a.org/v; touch " + tmp + "/pwned"])
    ok(!fs.existsSync(path.join(tmp, "pwned")), "a link with shell words in it runs nothing")
    r = run(["ytdlp", "video", "max", "mp3", out, "https://a.org/FAIL"])
    eq(r.status, 1); eq(lines(r), ["SEKAI|engine|ytdlp", "SEKAI|err|Unsupported URL: x"], "the error is one clean line")
    r = run(["ytdlp", "video", "max", "mp3", out, ""])
    ok(/SEKAI\|err\|There is no link/.test(r.stdout), "no link")
    r = run(["nonsense", "video", "max", "mp3", out, "https://a.org/v"])
    ok(/SEKAI\|err\|Unknown engine/.test(r.stdout), "unknown engine")
    // no yt-dlp on the path: says what to install (only when this machine has none of its own in /usr/bin)
    fs.unlinkSync(path.join(bin, "yt-dlp"))
    if (cp.spawnSync("sh", ["-c", "PATH=/usr/bin:/bin command -v yt-dlp"]).status !== 0) {
        r = run(["ytdlp", "video", "max", "mp3", out, "https://a.org/v"])
        ok(/yt-dlp is not installed/.test(r.stdout), "yt-dlp missing")
    }
    // cobalt: no instance set
    r = run(["cobalt", "video", "max", "mp3", out, "https://a.org/v"])
    ok(/No cobalt instance is set/.test(r.stdout), "cobalt without an instance")
    // a "~" folder means home
    put("yt-dlp", `echo "$@" > "${tmp}/ytargs"; exit 0`)
    run(["ytdlp", "video", "max", "mp3", "~/Vids", "https://a.org/v"])
    ok(fs.existsSync(path.join(tmp, "Vids")) && fs.readFileSync(path.join(tmp, "ytargs"), "utf8").includes("--paths " + path.join(tmp, "Vids")), "~ is the home folder")
    // ---- the engine chain, the login, the subtitles, the names, the picker (stand-ins for the programs) ----
    const calls = path.join(tmp, "calls")
    const fakeYtdlp = body => put("yt-dlp", `echo "yt-dlp $@" >> "${calls}"\n` + body)
    const NOVIDEO = 'echo "ERROR: [twitter] 1: No video could be found in this tweet" >&2; exit 1'
    const fakeGdl = body => put("gallery-dl", `echo "gallery-dl $@" >> "${calls}"\n` + body)
    const GDL_OK = `mkdir -p "${out}"; echo x > "${out}/pic.jpg"; echo "${out}/pic.jpg"; exit 0`
    const called = () => fs.existsSync(calls) ? fs.readFileSync(calls, "utf8") : ""
    const fresh = () => { try { fs.unlinkSync(calls) } catch (e) {} }

    // yt-dlp finds no video: gallery-dl is tried and saves the picture
    fakeYtdlp(NOVIDEO); fakeGdl(GDL_OK); fresh()
    r = run(["auto", "video", "720", "mp3", out, "https://x.com/a/status/1"])
    eq(r.status, 0, "chain ok: " + r.stdout)
    eq(lines(r).filter(l => l.startsWith("SEKAI|engine")), ["SEKAI|engine|ytdlp", "SEKAI|engine|gallerydl"], "yt-dlp first, then gallery-dl")
    ok(lines(r).includes("SEKAI|file|" + out + "/pic.jpg") && lines(r).slice(-1)[0] === "SEKAI|done", "the picture is the file")
    // in audio / mute mode a picture is no use: gallery-dl is not tried
    fresh(); r = run(["auto", "audio", "720", "mp3", out, "https://x.com/a/status/1"])
    ok(!/gallery-dl/.test(called()) && r.status === 1, "gallery-dl is not tried for sound only")
    // one that works stops the chain
    fakeYtdlp(`echo "SEKAI|title|T"; echo "SEKAI|file|${out}/T.mp4"; exit 0`); fresh()
    r = run(["auto", "video", "720", "mp3", out, "https://a.org/v"])
    ok(!/gallery-dl/.test(called()) && lines(r).slice(-1)[0] === "SEKAI|done", "a working first engine is the only one used")
    // a named engine is the only one
    fakeYtdlp(NOVIDEO); fresh()
    r = run(["ytdlp", "video", "720", "mp3", out, "https://x.com/a/status/1"])
    ok(!/gallery-dl/.test(called()) && /No video could be found/.test(r.stdout), "yt-dlp asked for by name: no fallback")
    // all fail: the useful message wins over "no video" / "unsupported"
    fakeGdl('echo "[gallery-dl][error] Unsupported URL" >&2; exit 64')
    r = run(["auto", "video", "720", "mp3", out, "https://x.com/a/status/1"])
    ok(/SEKAI\|err\|/.test(r.stdout) && r.status === 1, "everything failed: one error line")
    fakeYtdlp('echo "ERROR: [instagram] 1: Login required to view this" >&2; exit 1')
    r = run(["auto", "video", "720", "mp3", out, "https://instagram.com/p/x"])
    ok(/Login required/.test(r.stdout) && /Login from/.test(r.stdout), "a login failure points at the setting")
    r = run(["auto", "video", "720", "mp3", out, "https://instagram.com/p/x"], { SEKAI_COOKIES: "firefox" })
    ok(/Login required/.test(r.stdout) && !/Login from/.test(r.stdout), "no hint once a login is set")

    // the login, the subtitles, the names reach the programs; file wins over browser; no subtitles for sound only
    fakeYtdlp("exit 0"); fresh()
    run(["ytdlp", "video", "720", "mp3", out, "https://a.org/v"], { SEKAI_COOKIES: "firefox", SEKAI_SUBS: "en", SEKAI_NAMES: "classic" })
    let c = called()
    ok(/--cookies-from-browser firefox/.test(c) && /--write-subs/.test(c) && /--sub-langs en\.\*,en/.test(c) && /--embed-subs/.test(c) && /--output %\(extractor\)s_%\(id\)s\.%\(ext\)s/.test(c), "login, subtitles and names reach yt-dlp: " + c)
    fresh(); run(["ytdlp", "audio", "720", "mp3", out, "https://a.org/v"], { SEKAI_COOKIES_FILE: "~/c.txt", SEKAI_COOKIES: "firefox", SEKAI_SUBS: "en" })
    c = called(); ok(c.includes("--cookies " + path.join(tmp, "c.txt")) && !/cookies-from-browser/.test(c) && !/--write-subs/.test(c), "the cookies file wins; no subtitles for sound only")
    fresh(); run(["ytdlp", "video", "720", "mp3", out, "https://a.org/v"], { SEKAI_SUBS: "en; touch " + tmp + "/pwned2" })
    ok(!fs.existsSync(path.join(tmp, "pwned2")), "a subtitle language with shell words in it runs nothing")

    // the picker: gallery-dl lists several items, nothing is saved, the script ends WITHOUT "done"
    fakeYtdlp(NOVIDEO)
    fakeGdl(`case "$*" in *--get-urls*) printf 'https://pbs.example/a.jpg?name=orig\\nhttps://pbs.example/b.png\\nytdl:https://x.com/i/status/1\\n| https://parent/x\\n';; *) echo "${out}/should-not-run.jpg";; esac`)
    r = run(["auto", "video", "720", "mp3", out, "https://x.com/a/status/1"], { SEKAI_PICK: "1" })
    const L = lines(r)
    eq(L.filter(l => l.startsWith("SEKAI|item")).length, 3, "three items listed (the | line is not one)")
    ok(L.includes("SEKAI|choose|3") && !L.includes("SEKAI|done") && r.status === 0, "asked to choose, not done")
    ok(L.includes("SEKAI|item|photo\thttps://pbs.example/a.jpg?name=orig\thttps://pbs.example/a.jpg?name=orig") && L.includes("SEKAI|item|video\tytdl:https://x.com/i/status/1\t"), "a picture is its own thumbnail, a video has none")
    ok(!fs.existsSync(path.join(out, "should-not-run.jpg")), "nothing saved while asking")
    // the same without asking: it downloads
    fakeGdl(GDL_OK); fresh()
    r = run(["auto", "video", "720", "mp3", out, "https://x.com/a/status/1"])
    ok(lines(r).slice(-1)[0] === "SEKAI|done" && !lines(r).some(l => l.startsWith("SEKAI|item")), "no asking: it just downloads")
    // fetch: only what was chosen. A picture is fetched by curl, the ytdl: one by yt-dlp.
    put("curl", `echo "curl $@" >> "${calls}"; for a in "$@"; do last="$a"; done; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; prev="$a"; done; echo data > "$o"; exit 0`)
    fakeYtdlp(`echo "SEKAI|file|${out}/Vid.mp4"; exit 0`); fresh()
    r = run(["fetch", "video", "720", "mp3", out, "https://x.com/a/status/1"], { SEKAI_ITEMS: "photo\thttps://pbs.example/a.jpg?name=orig\nvideo\tytdl:https://x.com/i/status/1\n" })
    c = called()
    ok(r.status === 0 && /curl .*https:\/\/pbs\.example\/a\.jpg\?name=orig/.test(c) && /yt-dlp .*-- https:\/\/x\.com\/i\/status\/1/.test(c), "fetch: curl for the picture, yt-dlp for the video: " + c + r.stdout)
    ok(fs.existsSync(path.join(out, "a.jpg")) && lines(r).slice(-1)[0] === "SEKAI|done", "the picture got its own name from the address")
    r = run(["fetch", "video", "720", "mp3", out, "https://x"], { SEKAI_ITEMS: "" })
    ok(/Nothing was chosen/.test(r.stdout) && r.status === 1, "fetch with nothing chosen")
    fs.unlinkSync(path.join(bin, "curl"))

    // the temp folder is gone afterwards
    ok(!fs.readdirSync(os.tmpdir()).some(f => f.startsWith("sekai-dl.") && fs.statSync(path.join(os.tmpdir(), f)).mtimeMs > Date.now() - 60000), "no temporary folder is left behind")
} else {
    console.log("  (bash or mktemp missing: the script was not run)")
}
fs.rmSync(tmp, { recursive: true, force: true })

// ---- 6. the QML is wired to it ----
const check = require("../lib/qmlcheck")
const svc = read("services/DownloaderService.qml"), widget = read("modules/sekai/desktopWidgets/DownloaderWidget.qml")
const tile = read("modules/sekai/desktopWidgets/DownloaderTile.qml"), fill = read("modules/sekai/desktopWidgets/DownloadFill.qml")
const shell = read("shell.qml"), edit = read("services/EditMode.qml"), settings = read("modules/sekai/settings/SettingsPageDesktop.qml")
const presets = read("services/PresetWidgets.qml"), focus = read("modules/common/functions/FocusMath.js")
for (const [name, text] of [["DownloaderService.qml", svc], ["DownloaderWidget.qml", widget], ["DownloaderTile.qml", tile], ["DownloadFill.qml", fill]])
    eq(check(text, name), [], name + " has no duplicate ids / members and its brackets balance")
ok(/pragma Singleton/.test(svc) && /DownloadMath\.js/.test(svc), "the service is a singleton that uses the math")
for (const fn of ["snapshot", "restore", "persist", "setShown", "setPosition", "submit", "paste", "cancel", "retry", "remove", "clearFinished", "cycleMode", "cycleQuality", "cycleAudio", "openFolder", "recheck"])
    ok(new RegExp("function " + fn + "\\(").test(svc), "service has " + fn)
for (const sig of ["jobAdded", "jobFinished", "rejected"]) ok(new RegExp("signal " + sig + "\\(").test(svc), "signal " + sig)
ok(/DownloaderWidget \{\}/.test(shell) && /woke\(12\)/.test(shell) && /widgetId: "downloader"/.test(shell), "shell.qml loads it behind a focus gate")
ok(/target: "downloader"/.test(shell), "it has an ipc target")
for (const fn of ["toggle", "paste", "get", "cancel", "mode", "quality", "engine", "folder", "open", "clear", "status", "size", "resetPosition"])
    ok(new RegExp("function " + fn + "\\(").test(shell.slice(shell.indexOf('target: "downloader"'), shell.indexOf('target: "watertank"'))), "ipc " + fn)
ok(/id: "downloader", title: "Downloader"/.test(edit) && (edit.match(/"downloader"/g) || []).length >= 6, "Edit Desktop: shelf, on, home, add, remove, move")
ok(/id: "downloader"/.test(presets) && /"cobaltKey"/.test(presets), "the preset registry skips the key")
ok(/downloader: 11/.test(focus), "focus mode wakes it last")
for (const fn of ["togglePick", "pickAll", "confirmPick", "dropMask", "setCookies", "setCookiesFile", "setSubs", "setNames", "setAskWhich"])
    ok(new RegExp("function " + fn + "\\(").test(svc), "service has " + fn)
ok(/signal pickReady\(/.test(svc) && /status: "choosing"/.test(svc) && /SEKAI_PICK: \(root\.askWhich && !root\.tiny && !fetching\)/.test(svc), "the picker only asks at 2 x 2, and not on the second run")
ok(/haveGalleryDl/.test(svc) && /gallery-dl/.test(svc), "it looks for gallery-dl")
for (const k of ["cookies", "cookiesFile", "subs", "names", "askWhich"]) {
    ok(new RegExp('"' + k + '"').test(presets), "the preset skips " + k)
    ok(new RegExp(k + ": root\\." + k).test(svc), "the state file holds " + k)
}
for (const fn of ["cookies", "cookiesFile", "subs", "names", "ask"])
    ok(new RegExp("function " + fn + "\\(").test(shell.slice(shell.indexOf('target: "downloader"'), shell.indexOf('target: "watertank"'))), "ipc " + fn)
for (const w of ["setCookies", "setCookiesFile", "setSubs", "setNames", "setAskWhich"]) ok(new RegExp("DownloaderService\\." + w).test(settings), "settings: " + w)
ok(/id: "gallerydl"/.test(settings), "settings: gallery-dl engine")
ok(/id: picker/.test(widget) && /confirmPick/.test(widget) && /togglePick/.test(widget) && /pickAll/.test(widget), "the 2 x 2 has the picker")
ok(/choosing: DownloaderService\.pickJob !== null/.test(widget) && /property bool choosing/.test(tile), "the 1 x 1 knows a post waits")
ok(/yt-dlp/.test(read("../check-deps.sh")) && /gallery-dl/.test(read("../install-deps.sh")) && /gallery-dl/.test(read("../check-deps.sh")), "both programs are in the dependency scripts")
ok(/DownloaderService\.setShown/.test(settings) && /DownloaderService\.setCobaltUrl/.test(settings) && /DownloaderService\.setCobaltKey/.test(settings), "settings page")
ok(/WlrLayershell\.namespace: "sekaipop-downloader"/.test(widget) && /widgetId: "downloader"/.test(widget), "widget layer + edit id")
ok(!/WaterTankService\.|WaterTile|WaterFill|WaterMath|WTM\.|"watertank"/.test((widget + tile + svc).replace(/\/\/[^\n]*/g, "")), "no code of the water tank is left in the copy")
// every icon it draws is in the icon set
const icons = read("modules/common/functions/IconMap.js")
const used = new Set([...(widget + tile).matchAll(/name: "([a-z_0-9]+)"/g)].map(m => m[1]))
for (const i of ["download", "downloading", "check_circle", "error", "close", "refresh", "history", "folder_open", "delete", "movie", "music_note", "volume_off"]) used.add(i)
for (const i of used) ok(new RegExp("^\\s*" + i + ":", "m").test(icons), "icon " + i + " is in IconMap.js")
// the state file is private
const st = locate("scripts/state/downloader-state.sh")
ok(/umask 077/.test(fs.readFileSync(st, "utf8")), "the state file is mode 600 (it holds the cobalt key)")
ok(/SEKAI_DL_STATE/.test(svc) && !/"save", json/.test(svc), "the state goes to the script in the environment, not on its command line")
ok(/runner\.environment = \(\{[^}]*SEKAI_COBALT_KEY: root\.cobaltKey/.test(svc), "the key is put in the environment")
ok(!svc.split("\n").some(l => /exec\(/.test(l) && /cobaltKey/.test(l)), "and is on no command line")

console.log("downloader_unit: " + n + " checks passed")
