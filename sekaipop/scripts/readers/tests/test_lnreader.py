"""The novel reader's LNReader source: plugin catalog, install, the five plugin calls, ids, the HTTP
endpoints. Runs the real Node host (lnreader_host.js) with a fake plugin and a fake network, so it needs
`node` but no internet and no npm packages.
Run: python3 tests/test_lnreader.py"""
import os, sys, json, shutil, tempfile, threading, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
NOVEL = os.path.join(HERE, "..", "novel_server")
if not shutil.which("node"):
    print("SKIP: node is not installed")
    sys.exit(0)

TMP = tempfile.mkdtemp(prefix="lnreader-test-")
os.environ["HOME"] = TMP                                   # storage.py makes its folders at import
os.environ["SEKAIPOP_LNREADER_DIR"] = os.path.join(TMP, "lnreader")
sys.path.insert(0, NOVEL)

from providers import utils
import providers
from providers import lnreader as lr
import storage
import server

lr.SETUP.state, lr.SETUP.message = "ready", ""             # no npm in the test: the fake plugin needs none

# ── html -> paragraphs ──────────────────────────────────────────────────────
P = lr.html_to_paragraphs
assert P("<p>One</p><p>Two  &amp; <b>three</b></p>") == ["One", "Two & three"]
assert P("Line one<br>Line two<br/><br>Line three") == ["Line one", "Line two", "Line three"]
assert P("<div>A<script>evil()</script></div><style>p{}</style><h2>Head</h2>text") == ["A", "Head", "text"]
assert P("plain\n\n  text  here \n") == ["plain", "text here"]
assert P("") == [] and P(None) == []
assert P("<p>nbsp&nbsp;here</p>") == ["nbsp here"]

# ── ids ────────────────────────────────────────────────────────────────────
nid = lr.make_nid("fake", "/novel/a:b?x=1")
assert "/" not in nid and ":" not in nid, nid
assert lr.parse_nid(nid) == ("fake", "/novel/a:b?x=1")
cid = lr.make_cid("fake", "/novel/a:b?x=1", "https://fake.test/ch/1")
assert cid.count("/") == 1 and ":" not in cid, cid
assert lr.parse_cid(cid) == ("fake", "/novel/a:b?x=1", "https://fake.test/ch/1")
for bad in ("nopipe", "bad id~x"):
    try:
        lr.parse_nid(bad); raise SystemExit("accepted " + bad)
    except ValueError:
        pass

# download folders: short and unique even for a url-shaped id
long_cid = "lnreader:" + lr.make_cid("fake", "/n/" + "x" * 300, "/c/1")
d = storage._chapter_dir(long_cid)
assert all(len(part) < 200 for part in d.split(os.sep)), d
assert storage._safe("shadow-slave") == "shadow-slave"
assert storage._chapter_dir(long_cid) != storage._chapter_dir(long_cid.replace("/c/1", "/c/2").replace("%2Fc%2F1", "%2Fc%2F2"))

# ── a fake plugin, written the way lnreader-plugins compiles them ───────────
PLUGIN = r"""
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fetch_1 = require("@libs/fetch");
const filterInputs_1 = require("@libs/filterInputs");
const novelStatus_1 = require("@libs/novelStatus");
class FakePlugin {
  constructor() {
    this.id = "fake"; this.name = "Fake Site"; this.icon = "src/en/fake/icon.png";
    this.site = "https://fake.test"; this.version = "1.0.2";
    this.filters = { order: { type: filterInputs_1.FilterTypes.Picker, label: "Order", value: "popular",
                              options: [{ label: "Popular", value: "popular" }] } };
  }
  async popularNovels(pageNo, { showLatestNovels, filters }) {
    const kind = showLatestNovels ? "latest" : filters.order.value;
    const res = await (0, fetch_1.fetchApi)(`${this.site}/list?kind=${kind}&page=${pageNo}`);
    return (await res.json()).map(n => ({ name: n.name, path: n.path, cover: n.cover }));
  }
  async searchNovels(term, pageNo) {
    const res = await (0, fetch_1.fetchApi)(`${this.site}/search`, {
      method: "POST", body: new URLSearchParams({ q: term, page: String(pageNo) }),
      headers: { "X-Test": "yes" } });
    return (await res.json()).map(n => ({ name: n.name, path: n.path, cover: n.cover }));
  }
  async parseNovel(novelPath) {
    const res = await (0, fetch_1.fetchApi)(this.site + novelPath);
    const d = await res.json();
    return { path: novelPath, name: d.name, cover: d.cover, summary: d.summary, author: d.author,
             status: novelStatus_1.NovelStatus.Ongoing, genres: "Action, Fantasy ,Drama",
             totalPages: 2, chapters: d.chapters };
  }
  async parsePage(novelPath, page) {
    const res = await (0, fetch_1.fetchApi)(`${this.site}${novelPath}?chapters=${page}`);
    return { chapters: (await res.json()).chapters };
  }
  async parseChapter(chapterPath) {
    const res = await (0, fetch_1.fetchApi)(this.site + chapterPath);
    if (!res.ok) throw new Error("chapter " + res.status);
    return await res.text();
  }
}
exports.default = new FakePlugin();
"""
BROKEN = 'const c = require("cheerio"); exports.default = { parseNovel() {} };'
PLUGIN_URL = "https://plugins.test/.dist/fake.js"
REPO_URL = "https://plugins.test/.dist/plugins.min.json"
CATALOG = [
    {"id": "fake", "name": "Fake Site", "site": "https://fake.test", "lang": "English", "version": "1.0.2",
     "url": PLUGIN_URL, "iconUrl": "https://plugins.test/icon.png"},
    {"id": "needscheerio", "name": "Needs Cheerio", "site": "https://c.test", "lang": "English", "version": "1.0.0",
     "url": "https://plugins.test/.dist/needscheerio.js", "iconUrl": ""},
    {"id": "../evil", "name": "Evil", "site": "", "lang": "x", "version": "1", "url": "https://x/e.js"},
]

SECOND_URL = "https://second.test/plugins.min.json"
DOWN_URL = "https://down.test/plugins.min.json"
SECOND_CATALOG = [
    {"id": "second", "name": "Second Site", "site": "https://second.test", "lang": "Spanish", "version": "2.0.0",
     "url": "https://second.test/second.js", "iconUrl": ""},
    {"id": "fake", "name": "Other Fake", "site": "https://other.test", "lang": "English", "version": "9.9.9",
     "url": "https://second.test/fake.js", "iconUrl": ""},     # same id as the first list's: the earlier list wins
]

# ── the real utils.request, against a local server ─────────────────────────
import http.server, socketserver
hits = {"429": 0}

class _H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, status, body=b"", ctype="application/json", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.path == "/ok":
            self._send(200, json.dumps({"ua": self.headers.get("User-Agent"), "x": self.headers.get("X-Test")}).encode())
        elif self.path == "/redir":
            self._send(302, b"", extra={"Location": "/ok"})
        elif self.path == "/429":
            hits["429"] += 1
            if hits["429"] == 1:
                self._send(429, b"slow down", extra={"Retry-After": "0"})
            else:
                self._send(200, b"fine")
        else:
            self._send(404, b"missing", "text/plain")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        self._send(200, json.dumps({"ct": self.headers.get("Content-Type"), "body": body.decode()}).encode())

class _S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
local = _S(("127.0.0.1", 0), _H)
threading.Thread(target=local.serve_forever, daemon=True).start()
L = f"http://127.0.0.1:{local.server_address[1]}"

st, hd, body, final = utils.request("GET", L + "/ok", {"user-agent": "PluginUA", "X-Test": "1"})
got = json.loads(body)
assert st == 200 and got == {"ua": "PluginUA", "x": "1"}, got                 # a plugin's header replaces the default, any case
assert hd["content-type"] == "application/json" and "content-length" not in hd and final == L + "/ok"
st, hd, body, final = utils.request("GET", L + "/redir")
assert st == 200 and final == L + "/ok", (st, final)                          # redirects followed, final url reported
st, hd, body, final = utils.request("POST", L + "/echo", {"Content-Type": "application/x-www-form-urlencoded"}, b"a=1&b=2")
assert json.loads(body) == {"ct": "application/x-www-form-urlencoded", "body": "a=1&b=2"}
st, hd, body, final = utils.request("GET", L + "/nothing")
assert st == 404 and body == b"missing"                                       # an error status is returned, not raised
st, hd, body, final = utils.request("GET", L + "/429")
assert st == 200 and body == b"fine" and hits["429"] == 2                     # a 429 is waited out and retried
try:
    utils.request("PUT", L + "/ok"); raise SystemExit("PUT should be refused")
except ValueError:
    pass
try:
    utils.request("GET", "http://127.0.0.1:1/x", timeout=3); raise SystemExit("a dead port should raise")
except SystemExit:
    raise
except Exception:
    pass                                                                      # connection failures raise: the plugin sees a rejected fetch
local.shutdown()

# ── a fake network ──────────────────────────────────────────────────────────
calls = []
NOVELS = [{"name": f"Novel {i}", "path": f"/novel/n{i}", "cover": f"/c/{i}.jpg"} for i in range(1, 4)]

def fake_request(method, url, headers=None, body=None, timeout=30):
    calls.append((method, url, dict(headers or {}), body))
    j = lambda o, status=200: (status, {"content-type": "application/json"}, json.dumps(o).encode(), url)
    if url.startswith("https://fake.test/list?"):
        page = int(url.rsplit("=", 1)[1])
        kind = url.split("kind=")[1].split("&")[0]
        return j(NOVELS if page == 1 else NOVELS[:1] + [{"name": "Novel 9", "path": "/novel/n9"}] if page == 2
                 else NOVELS)                                   # page 3 repeats page 1: the list ends
    if url == "https://fake.test/search":
        assert method == "POST" and headers.get("X-Test") == "yes", (method, headers)
        assert headers.get("Content-Type") == "application/x-www-form-urlencoded", headers
        assert body == b"q=dragon&page=1", body
        return j([{"name": "Dragon Novel", "path": "/novel/dragon"}])
    if url == "https://fake.test/novel/n1":
        return j({"name": "Novel 1", "cover": "/c/1.jpg", "author": "Au Thor",
                  "summary": "<p>First line</p><p>Second line</p>",
                  "chapters": [{"name": "Prologue", "path": "/novel/n1/ch1", "chapterNumber": 1, "releaseTime": "2026-11-04"},
                               {"name": "The start", "path": "/novel/n1/ch2", "chapterNumber": 2, "releaseTime": "Nov 5, 2026"}]})
    if url == "https://fake.test/novel/n1?chapters=2":
        return j({"chapters": [{"name": "", "path": "/novel/n1/ch3"},
                               {"name": "Dup", "path": "/novel/n1/ch2"},       # a repeat is dropped
                               {"name": "Fourth", "path": "/novel/n1/ch4", "chapterNumber": 4, "releaseTime": "3 months ago"}]})
    if url.startswith("https://fake.test/novel/n1/ch"):
        if url.endswith("ch4"):
            return (404, {}, b"nope", url)
        return (200, {"content-type": "text/html"}, f"<div><p>Text of {url[-3:]}.</p><p>Second para</p></div>".encode(), url)
    if url == PLUGIN_URL:
        return (200, {}, PLUGIN.encode(), url)
    if url == "https://plugins.test/.dist/needscheerio.js":
        return (200, {}, BROKEN.encode(), url)
    if url == "https://fake.test/c/1.jpg":
        return (200, {"content-type": "image/png"}, b"\x89PNG", url)
    raise AssertionError("unexpected request " + url)

utils.request = fake_request
utils.fetch = lambda url, extra=None, timeout=30, form=None: fake_request("GET", url)[2].decode()
fetched = []
OFFICIAL = "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.10/.dist/plugins.min.json"
def fake_fetch_json(url, extra=None, timeout=30):
    fetched.append(url)
    if url in (REPO_URL, OFFICIAL):
        return CATALOG
    if url == SECOND_URL:
        return SECOND_CATALOG
    if url == DOWN_URL:
        raise OSError("connection refused")
    if url == lr.TAGS_API:
        return [{"name": "v3.0.9", "type": "dir"}, {"name": "v3.0.10", "type": "dir"},
                {"name": "v2.9.0", "type": "dir"}, {"name": "README.md", "type": "file"}]
    raise AssertionError("unexpected json " + url)
utils.fetch_json = fake_fetch_json

ln = lr.LNReaderProvider()
assert lr.LNReaderProvider() is ln and providers.provider_for("lnreader:x~y") is ln
assert providers.active_name() == "lnreader"
assert [p["name"] for p in providers.list_all()] == ["lnreader"]                    # legacy ones hidden
assert providers.provider_for("freewebnovel:novel/x").name == "freewebnovel"        # but old ids still resolve

try:
    ln.hot(); raise SystemExit("hot() with no source should fail")
except ValueError as e:
    assert "No source" in str(e), e

# ── catalog: with no address set the newest tag folder is found, then its list read ──
fetched.clear()
cat = ln.catalog()
assert fetched == [lr.TAGS_API, OFFICIAL], fetched                 # v3.0.10 beats v3.0.9 (numeric, not text, order)
assert cat["total"] == 3 and {p["id"] for p in cat["plugins"]} == {"fake", "needscheerio", "../evil"}
assert not any(p["installed"] for p in cat["plugins"])

# a repo address of the user's own is used as given, with no lookup
ln.set_repo(REPO_URL)
fetched.clear()
assert ln.catalog()["repo"] == REPO_URL and fetched == [REPO_URL], fetched
assert ln.catalog()["total"] == 3 and fetched == [REPO_URL]         # the second read is cached
for bad in ("ftp://x", "javascript:1"):
    try:
        ln.set_repo(bad); raise SystemExit("accepted repo " + bad)
    except ValueError:
        pass
assert ln.catalog()["repo"] == REPO_URL                              # a refused address changed nothing

# ── several repositories ────────────────────────────────────────────────────
assert ln.repos()["repos"] == [{"id": REPO_URL, "name": REPO_URL, "official": False}]
assert [x["url"] for x in ln.repos()["suggested"]] == ["official"]          # the official list, one tap away
r = ln.change_repos(add=SECOND_URL)
assert [x["id"] for x in r["repos"]] == [REPO_URL, SECOND_URL], r
fetched.clear()
cat = ln.catalog()
assert fetched == [REPO_URL, SECOND_URL] and cat["total"] == 4 and cat["warnings"] == [], (fetched, cat["total"])
by_id = {p["id"]: p for p in cat["plugins"]}
assert by_id["fake"]["version"] == "1.0.2" and by_id["fake"]["repo"] == REPO_URL      # the earlier list wins
assert by_id["second"]["repo"] == SECOND_URL
ln.change_repos(add=SECOND_URL)                                              # a repeat is not added twice
assert len(ln.repos()["repos"]) == 2
for bad in ("ftp://x", "nonsense", "javascript:1"):
    try:
        ln.change_repos(add=bad); raise SystemExit("accepted repository " + bad)
    except ValueError:
        pass
assert len(ln.repos()["repos"]) == 2
ln.change_repos(add="official")
fetched.clear()
assert ln.catalog()["total"] == 4 and lr.TAGS_API in fetched and OFFICIAL in fetched, fetched
assert ln.repos()["suggested"] == [] and ln.repos()["repos"][-1] == {"id": "official", "name": lr.OFFICIAL_NAME, "official": True}
ln.change_repos(remove="official")
# one list down: the others still show, and the page says which one failed
ln.change_repos(add=DOWN_URL)
cat = ln.catalog(True)
assert cat["total"] == 4 and len(cat["warnings"]) == 1 and DOWN_URL in cat["warnings"][0], cat["warnings"]
# every list down: an error, not an empty list
ln.change_repos(remove=REPO_URL); ln.change_repos(remove=SECOND_URL)
try:
    ln.catalog(True); raise SystemExit("an empty catalog instead of an error")
except RuntimeError as e:
    assert "could not load the plugin list" in str(e), e
ln.change_repos(remove=DOWN_URL)
assert ln.repos()["repos"] == [] and ln.catalog(True)["plugins"] == []        # none at all: nothing to list
ln.set_repo(REPO_URL)                                                        # the one-address call still works
assert ln.repos()["repos"][0]["id"] == REPO_URL and ln.catalog(True)["repo"] == REPO_URL and ln.repos()["repos"].__len__() == 1
ln.set_repo("")
assert [x["id"] for x in ln.repos()["repos"]] == ["official"] and ln.catalog(True)["repo"] == ""
ln.set_repo(REPO_URL)

# an older state.json (one address, "" = official) becomes the list
import shutil as _sh
_keep = open(lr.STATE_FILE).read() if os.path.exists(lr.STATE_FILE) else None
os.makedirs(lr.DATA_DIR, exist_ok=True)
for old, want in (({"repo": ""}, ["official"]), ({"repo": REPO_URL}, [REPO_URL]), ({}, ["official"]),
                  ({"repos": [SECOND_URL, "junk", SECOND_URL, "official"]}, [SECOND_URL, "official"])):
    with open(lr.STATE_FILE, "w") as f:
        json.dump(old, f)
    assert lr.LNReaderProvider._load_state()["repos"] == want, (old, lr.LNReaderProvider._load_state())
if _keep is None:
    os.remove(lr.STATE_FILE)
else:
    open(lr.STATE_FILE, "w").write(_keep)

# ── install / select / uninstall ────────────────────────────────────────────
try:
    ln.install("../evil"); raise SystemExit("installed a path-traversal id")
except ValueError:
    pass
assert ln.install("fake")["active"] == "fake"                    # first install becomes the source
assert os.path.exists(os.path.join(lr.PLUGINS_DIR, "fake.js"))
src = ln.sources()
assert src["active"] == "fake" and [s["id"] for s in src["sources"]] == ["fake"]
assert src["sources"][0]["iconUrl"].startswith("http://127.0.0.1:5151/image?url=")
assert ln.catalog()["plugins"][0]["installed"] and not ln.catalog()["plugins"][0]["update"]
assert json.load(open(lr.STATE_FILE))["active"] == "fake"        # survives a restart
ln.install("needscheerio")
assert ln.select("needscheerio")["active"] == "needscheerio"
try:
    ln.select("nope"); raise SystemExit("selected an uninstalled source")
except ValueError:
    pass
try:
    ln.hot(); raise SystemExit("plugin without cheerio should fail")
except RuntimeError as e:
    assert "cheerio" in str(e), e                                 # says what is missing
ln.select("fake")

# ── update all: every installed source that has a newer version ─────────────
CATALOG[0]["version"] = "1.0.3"
assert [p["update"] for p in ln.catalog(True)["plugins"] if p["id"] == "fake"] == [True]
res = ln.update_all()
assert res == {"ok": True, "updated": 1, "failed": []}, res
assert not any(p["update"] for p in ln.catalog()["plugins"])
assert ln.update_all()["updated"] == 0                                        # nothing left to do
CATALOG[0]["version"] = "1.0.2"
ln.catalog(True)
ln.install("fake")                                                            # back where the next tests expect it

# ── browsing ────────────────────────────────────────────────────────────────
hot = ln.hot_page(1)
assert [c["title"] for c in hot["results"]] == ["Novel 1", "Novel 2", "Novel 3"] and hot["hasMore"]
assert hot["results"][0]["id"] == "fake~%2Fnovel%2Fn1"
assert hot["results"][0]["image"] == "http://127.0.0.1:5151/image?url=https%3A%2F%2Ffake.test%2Fc%2F1.jpg"
assert any("kind=popular&page=1" in c[1] for c in calls)           # default filter values reached the plugin
h2 = ln.hot_page(2)
assert [c["title"] for c in h2["results"]] == ["Novel 9"] and h2["hasMore"]     # the repeat of Novel 1 is dropped
h3 = ln.hot_page(3)
assert h3["results"] == [] and not h3["hasMore"]                                # nothing new: the list ends
lat = ln.latest(1)
assert lat["results"] and any("kind=latest&page=1" in c[1] for c in calls)
s = ln.search("dragon")
assert s["results"][0]["title"] == "Dragon Novel" and s["nextPage"] == 2       # POST body and headers got through

# ── info ────────────────────────────────────────────────────────────────────
info = ln.info("fake~%2Fnovel%2Fn1")
assert info["title"] == "Novel 1" and info["author"] == "Au Thor" and info["status"] == "Ongoing"
assert info["genres"] == ["Action", "Fantasy", "Drama"]
assert info["description"] == "First line\nSecond line"
assert [c["chapter"] for c in info["chapters"]] == ["1", "2", "3", "4"], info["chapters"]   # page 2 merged, repeat dropped
assert [c["title"] for c in info["chapters"]] == ["Prologue", "The start", "Chapter 3", "Fourth"]
assert info["chapters"][0]["id"] == "fake~%2Fnovel%2Fn1/%2Fnovel%2Fn1%2Fch1"
assert not info["partial"]

# each row says when it was released (what the source printed), and where it sits in the source's list
assert [c["publishAt"] for c in info["chapters"]] == ["2026-11-04T12:00:00Z", "2026-11-05T12:00:00Z", "", ""], info["chapters"]
assert [c["releasedText"] for c in info["chapters"]] == ["", "", "", "3 months ago"], info["chapters"]   # too loose for a date: kept as said
assert [c["index"] for c in info["chapters"]] == [1, 2, 3, 4]
assert all(c["kind"] == "chapter" and c["volume"] == "" for c in info["chapters"])

# ── release dates ───────────────────────────────────────────────────────────
from datetime import datetime, timezone
NOW = datetime(2026, 11, 8, 10, 0, 0, tzinfo=timezone.utc)
R = lambda v: lr.parse_release(v, NOW)
assert R("2026-11-04") == ("2026-11-04T12:00:00Z", "")
assert R("2026-11-04T08:30:00+08:00") == ("2026-11-04T00:30:00Z", "")
assert R("Nov 4, 2026") == R("4 November 2026") == R("November 4th, 2026") == ("2026-11-04T12:00:00Z", "")
assert R("1730000000000") == R(1730000000) == ("2024-10-27T03:33:20Z", "")
assert R("25/12/2025") == R("12/25/2025") == ("2025-12-25T12:00:00Z", "")
assert R("04/05/2024") == ("", "04/05/2024")                  # which is the month? the site's words stay
assert R("5 days ago") == ("2026-11-03T10:00:00Z", "") and R("an hour ago") == ("2026-11-08T09:00:00Z", "")
assert R("yesterday") == ("2026-11-07T10:00:00Z", "")
assert R("2 months ago") == ("", "2 months ago") and R("10 days ago") == ("", "10 days ago")
assert R(None) == R("") == R(0) == R("0000-00-00") == R("null") == ("", "")
assert R("x" * 80) == ("", "")                                # a sentence is not a date

# ── volumes ─────────────────────────────────────────────────────────────────
V = lr.volume_info
assert V("Volume 2") == ("volume", "2") and V("Vol. 3") == ("volume", "3")
assert V("Volume 1 - Chapter 10: What Lies Ahead") == ("chapter", "1") and V("Vol.3 Ch.4") == ("chapter", "3")
assert V("Chapter 5") == V("Prologue") == V("Volumes of Light") == ("chapter", "")

# ── chapter: text, prev/next from the list ──────────────────────────────────
ch = ln.chapter(info["chapters"][1]["id"])
assert ch["paragraphs"] == ["Text of ch2.", "Second para"] and ch["wordCount"] == 5
assert ch["title"] == "The start"
assert ch["prevId"] == info["chapters"][0]["id"] and ch["nextId"] == info["chapters"][2]["id"]
assert ln.chapter(info["chapters"][0]["id"])["prevId"] == ""
try:
    ln.chapter(info["chapters"][3]["id"]); raise SystemExit("a 404 chapter should fail")
except RuntimeError as e:
    assert "chapter 404" in str(e), e

# ── image proxy ─────────────────────────────────────────────────────────────
body, ctype = ln.fetch_image("https://fake.test/c/1.jpg")
assert body == b"\x89PNG" and ctype == "image/png"
assert calls[-1][2].get("Referer") == "https://fake.test/"        # the source's own site as referer

# ── through the HTTP server ─────────────────────────────────────────────────
httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{httpd.server_address[1]}"

def get(path):
    try:
        with urllib.request.urlopen(base + path, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

def post(path, body):
    req = urllib.request.Request(base + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

st, data = get("/hot?page=1")
assert st == 200 and data["results"][0]["id"] == "lnreader:fake~%2Fnovel%2Fn1" and data["hasMore"], data
st, data = get("/search?q=dragon&page=1")
assert st == 200 and data["results"][0]["id"] == "lnreader:fake~%2Fnovel%2Fdragon", data
st, data = get("/info?id=" + urllib.request.quote("lnreader:fake~%2Fnovel%2Fn1", safe=""))
assert st == 200 and data["id"] == "lnreader:fake~%2Fnovel%2Fn1" and data["chapters"][0]["id"].startswith("lnreader:"), data
cid0 = data["chapters"][0]["id"]
st, data = get("/chapter?id=" + urllib.request.quote(cid0, safe=""))
assert st == 200 and data["paragraphs"][0] == "Text of ch1." and data["nextId"].startswith("lnreader:"), data
st, data = get("/lnreader/status")
assert st == 200 and data["node"]["state"] == "ready" and data["active"] == "fake", data
st, data = get("/lnreader/catalog")
assert st == 200 and data["total"] == 3 and any(p["installed"] for p in data["plugins"])
st, data = post("/lnreader/select", {"id": "needscheerio"})
assert st == 200 and data["active"] == "needscheerio"
st, data = post("/lnreader/select", {"id": "fake"})
st, data = post("/lnreader/uninstall", {"id": "needscheerio"})
assert st == 200 and data["active"] == "fake", data
st, data = post("/lnreader/uninstall", {"id": "fake"})
assert st == 200 and data["active"] == ""
st, data = get("/hot?page=1")
assert st == 400 and "No source" in data["error"], (st, data)       # the panel shows this message
st, data = post("/lnreader/install", {"id": "fake"})
assert st == 200 and data["active"] == "fake"
st, data = get("/lnreader/repos")
assert st == 200 and [x["id"] for x in data["repos"]] == [REPO_URL] and data["suggested"][0]["url"] == "official", data
st, data = post("/lnreader/repos", {"add": SECOND_URL})
assert st == 200 and [x["id"] for x in data["repos"]] == [REPO_URL, SECOND_URL], data
st, data = post("/lnreader/repos", {"add": "gopher://x"})
assert st == 400
st, data = post("/lnreader/repos", {"remove": SECOND_URL})
assert st == 200 and [x["id"] for x in data["repos"]] == [REPO_URL], data
st, data = post("/lnreader/update-all", {})
assert st == 200 and data["ok"] and data["updated"] == 0, data
st, data = post("/lnreader/repo", {"url": "gopher://x"})
assert st == 400

# the old sources still answer for ids saved under their prefix (here only the parse of the prefix)
assert providers.strip_prefix("chikari:some-slug") == ("chikari", "some-slug")

# a plugin that uses the repo's "@/" alias and the small helper libs (the Novel Fire error: needs "@/types/constants")
ALIAS = r"""
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const constants_1 = require("@/types/constants");
const filters_1 = require("@/types/filters");
const plugin_1 = require("@/types/plugin");
const utils_1 = require("@libs/utils");
const showToast_1 = require("@libs/showToast");
class A { constructor() { this.id = "aliasplug"; this.name = "Alias"; this.site = "https://a.test"; this.version = "1.0.0";
  this.filters = { x: { type: filters_1.FilterTypes.TextInput, label: "x", value: "" } }; }
  async popularNovels() { return [{ name: "n", path: "/n", cover: constants_1.defaultCover }]; }
  async searchNovels() { return []; }
  async parseNovel(p) { showToast_1.showToast("hi"); return { path: p, name: utils_1.utf8ToBase64("ab"), status: constants_1.NovelStatus.Completed, chapters: [] }; }
  async parseChapter() { return ""; } }
exports.default = new A();
"""
os.makedirs(lr.PLUGINS_DIR, exist_ok=True)
with open(os.path.join(lr.PLUGINS_DIR, "aliasplug.js"), "w") as f:
    f.write(ALIAS)
m = lr._HOST.meta("aliasplug")
assert m["name"] == "Alias" and m["filters"]["x"]["type"] == "Text", m
r = lr._HOST.call("aliasplug", "parseNovel", "/n")
assert r["name"] == "YWI=" and r["status"] == "Completed", r
r = lr._HOST.call("aliasplug", "popularNovels", 1, False)
assert r[0]["cover"].startswith("https://") and "coverNotAvailable" in r[0]["cover"], r

httpd.shutdown()
lr._HOST.stop()
shutil.rmtree(TMP, ignore_errors=True)
print("ok: LNReader provider")
