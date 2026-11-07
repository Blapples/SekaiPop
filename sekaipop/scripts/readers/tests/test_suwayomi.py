"""The Suwayomi provider, with Suwayomi mocked (no network, no Suwayomi needed).
The start / stop part runs a real child process (a tiny local web server) to prove the whole
process group is ended.
Run: python3 tests/test_suwayomi.py"""
import os, json, tempfile, threading, importlib.util, socket, time, signal
import urllib.request, urllib.error, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["XDG_DATA_HOME"] = tempfile.mkdtemp()                # no launcher from a real install
os.environ.pop("SEKAIPOP_SW_CMD", None); os.environ.pop("SEKAIPOP_SW_URL", None)
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR       = tmp
ms.MATCH_FILE     = os.path.join(tmp, "anilist_matches.json")
ms.PROVIDER_FILE  = os.path.join(tmp, "provider.json")
ms.DOWNLOADS_DIR  = os.path.join(tmp, "downloads"); os.makedirs(ms.DOWNLOADS_DIR)
ms.FAVORITES_FILE = os.path.join(tmp, "favorites.json")
ms.SW_LOG         = os.path.join(tmp, "suwayomi.log")

# ── 1. Suwayomi is offered only when it is set up; ids say which provider they belong to
assert ms.SW_ENABLED is False                                   # no SEKAIPOP_SW_* in this environment
assert [p["id"] for p in ms.provider_status()["providers"]] == ["weebcentral", "mangadex"]
try:
    ms.provider_set("suwayomi"); raise SystemExit("suwayomi accepted while not set up")
except ValueError:
    pass
ms.SW_ENABLED = True
assert [p["id"] for p in ms.provider_set("suwayomi")["providers"]] == ["weebcentral", "mangadex", "suwayomi"]
ms._prov["v"] = None                                            # as after a restart
assert ms.provider_get() == "suwayomi"
ms.SW_ENABLED = False
ms._prov["v"] = None
assert ms.provider_get() == "weebcentral"                       # the choice outlives the setup: fall back, do not break
ms.SW_ENABLED = True
assert ms.provider_of("sw-12") == "suwayomi" and ms.provider_of("md-x") == "mangadex"
assert ms.provider_of("01J76XYABC/Some-Series") == "weebcentral" and ms.provider_of("") == "weebcentral"
assert ms._mkey("42", "weebcentral") == "42" and ms._mkey("42", "mangadex") == "42@mangadex"
assert ms._mkey("42", "suwayomi") == "42@suwayomi"

# ── a fake Suwayomi: routes by the GraphQL text, thread-safe call log
calls, calls_lock = [], threading.Lock()
SOURCES = [
    {"id": "30", "name": "Zeta Scans", "lang": "en", "supportsLatest": True,  "isNsfw": False},
    {"id": "10", "name": "Alpha Reader", "lang": "en", "supportsLatest": True,  "isNsfw": False},
    {"id": "20", "name": "No Latest",   "lang": "en", "supportsLatest": False, "isNsfw": False},
    {"id": "40", "name": "Spicy",       "lang": "en", "supportsLatest": True,  "isNsfw": True},
    {"id": "50", "name": "Francais",    "lang": "fr", "supportsLatest": True,  "isNsfw": False},
    {"id": "60", "name": "Multi",       "lang": "all", "supportsLatest": True, "isNsfw": False},
]


def mg(mid, title, status="ONGOING", thumb=None, author="A. Writer, B. Drawer", artist="B. Drawer"):
    return {"id": mid, "title": title, "thumbnailUrl": thumb if thumb is not None else f"/api/v1/manga/{mid}/thumbnail",
            "status": status, "genre": ["Action", "Fantasy"], "description": " A story. ", "author": author, "artist": artist}


def fake_gql(handlers):
    def gql(query, variables=None, timeout=60):
        with calls_lock:
            calls.append((query.split("(")[0].split("{")[0].strip() or query[:30], variables))
        for key, fn in handlers.items():
            if key in query:
                return fn(variables or {})
        raise AssertionError("unexpected query " + query[:60])
    ms.sw_gql = gql


def reset():
    ms._cache.clear(); ms._img_cache.clear(); calls.clear()


# ── 2. which sources are asked: language, NSFW, order, a cap, and a clear error when there are none
fake_gql({"sources": lambda v: {"sources": {"nodes": list(SOURCES)}}})
reset()
names = [s["name"] for s in ms._sw_sources()]
assert names == ["Alpha Reader", "Multi", "No Latest", "Zeta Scans"], names   # en + all, no NSFW, by name
ms.SW_NSFW = True; reset()
assert "Spicy" in [s["name"] for s in ms._sw_sources()]; ms.SW_NSFW = False
ms.SW_SOURCES = ["30", "10"]; reset()
assert [s["name"] for s in ms._sw_sources()] == ["Zeta Scans", "Alpha Reader"]   # your order is kept
ms.SW_SOURCES = []
many = [{"id": str(i), "name": f"S{i:02d}", "lang": "en", "supportsLatest": True, "isNsfw": False} for i in range(30)]
fake_gql({"sources": lambda v: {"sources": {"nodes": many}}}); reset()
assert len(ms._sw_sources()) == ms.SW_MAX_SOURCES
fake_gql({"sources": lambda v: {"sources": {"nodes": [SOURCES[4]]}}}); reset()
try:
    ms._sw_sources(); raise SystemExit("no sources accepted")
except RuntimeError as e:
    assert "install an extension" in str(e), e

# ── 3. search: every source is asked, answers are interleaved, a failing one is skipped
def by_source(table):
    def fn(v):
        i = v["input"]
        r = table[i["source"]]
        if isinstance(r, Exception):
            raise r
        return {"fetchSourceManga": {"hasNextPage": i["page"] < 3, "mangas": r}}
    return fn

ALPHA = [mg(1, "Solo Leveling"), mg(2, "Alpha Two"), mg(3, "Alpha Three")]
ZETA  = [mg(11, "Solo Leveling"), mg(12, "Zeta Two")]
table = {"10": ALPHA, "20": [], "30": ZETA, "60": [mg(21, "Multi One", thumb="https://cdn.example/x.jpg")]}
fake_gql({"sources": lambda v: {"sources": {"nodes": list(SOURCES)}}, "fetchSourceManga": by_source(table)}); reset()
r = ms.sw_search("solo")
ids = [x["id"] for x in r["results"]]
assert ids == ["sw-1", "sw-21", "sw-11", "sw-2", "sw-12", "sw-3"], ids        # Alpha, Multi, Zeta, then the next of each
row = r["results"][0]
assert row["type"] == "Alpha Reader" and row["status"] == "Ongoing" and row["tags"] == ["Action", "Fantasy"], row
assert "127.0.0.1%3A4567%2Fapi%2Fv1%2Fmanga%2F1%2Fthumbnail" in row["image"], row["image"]   # proxied, through this server
assert "cdn.example%2Fx.jpg" in r["results"][1]["image"]                       # an absolute link is kept as it is
assert r["hasMore"] is True and r["nextOffset"] == 20
sent = [v["input"] for q, v in calls if q.startswith("mutation")]
assert all(i["type"] == "SEARCH" and i["query"] == "solo" and i["page"] == 1 for i in sent) and len(sent) == 4, sent
calls.clear(); ms.sw_search("solo", offset=40)
assert {v["input"]["page"] for q, v in calls if q.startswith("mutation")} == {3}          # offset 40 = page 3

table["30"] = RuntimeError("zeta is down"); reset()                           # one source failing is not fatal
assert [x["id"] for x in ms.sw_search("solo")["results"]][:2] == ["sw-1", "sw-21"]
table.update({"10": RuntimeError("a down"), "20": RuntimeError("b down"), "60": RuntimeError("m down")}); reset()
try:
    ms.sw_search("solo"); raise SystemExit("all sources failing looked like no results")
except RuntimeError as e:
    assert "down" in str(e)
table.update({"10": ALPHA, "20": [], "30": ZETA, "60": []})

# ── 4. latest: only sources that support it; the shape the panel's latest list reads
reset()
lt = ms.sw_latest(2)
sent = [v["input"] for q, v in calls if q.startswith("mutation")]
assert {i["source"] for i in sent} == {"10", "30", "60"} and all(i["type"] == "LATEST" and i["page"] == 2 for i in sent), sent
assert all("query" not in i for i in sent)
assert lt["nextPage"] == 3 and lt["hasMore"] is True
assert set(lt["results"][0]) == {"id", "title", "image", "status", "type", "chapter", "updatedAt"}, lt["results"][0]
n = len(calls); ms.sw_latest(2); assert len(calls) == n                       # cached

# ── 5. matching by name
def al_media(aid=105398, english="Solo Leveling", romaji="Na Honjaman Level-Up", native=None, syn=()):
    return {"id": aid, "title": {"english": english, "romaji": romaji, "native": native},
            "synonyms": list(syn), "startDate": {"year": 2018}, "countryOfOrigin": "KR"}

reset()
c = ms.sw_candidates(al_media())
assert c[0]["id"] == "sw-1" and c[0]["score"] >= ms.MATCH_MIN, c               # equal scores: the earlier source stays first
assert {x["id"] for x in c if x["score"] >= ms.MATCH_MIN} == {"sw-1", "sw-11"}
n = len(calls)                                                                 # a perfect name stops the search at once
assert len([1 for q, v in calls if q.startswith("mutation")]) == 4, n
table.update({"10": [mg(1, "Cooking With Cats")], "30": []}); reset()
c = ms.sw_candidates(al_media(10, english="Berserk", romaji="Berserk"))
assert c and c[0]["score"] < ms.MATCH_MIN, c                                   # nothing alike: the user picks
table.update({"10": RuntimeError("x"), "30": RuntimeError("y"), "60": RuntimeError("z"), "20": RuntimeError("w")}); reset()
try:
    ms.sw_candidates(al_media(11)); raise SystemExit("error swallowed")
except RuntimeError:
    pass
table.update({"10": ALPHA, "20": [], "30": ZETA, "60": []})

# ── 6. chapters: one per number, -1 is "no number", 0 is a number, dates are ISO, extras last
def ch(cid, num, name="", order=0, when="1700000000000"):
    return {"id": cid, "name": name, "chapterNumber": num, "scanlator": "", "uploadDate": when, "sourceOrder": order}

feed = [ch(5, 10.0, "Chapter 10", 0), ch(4, 2.5, "Chapter 2.5", 1), ch(3, 2.0, "Chapter 2", 2),
        ch(33, 2.0, "Chapter 2 (other group)", 5), ch(2, 1.0, "", 3), ch(1, 0.0, "Prologue", 4),
        ch(9, -1.0, "Special Story", 6, when="0"), ch(8, -1.0, "", 7)]
fake_gql({"fetchChapters": lambda v: {"fetchChapters": {"chapters": list(feed)}}})
out = ms._sw_chapters(7)
assert [c["id"] for c in out] == ["sw-1", "sw-2", "sw-3", "sw-4", "sw-5", "sw-9", "sw-8"], [c["id"] for c in out]
assert [c["index"] for c in out] == list(range(7))
by = {c["id"]: c for c in out}
assert by["sw-3"]["title"] == "Chapter 2" and by["sw-2"]["title"] == "Chapter 1" and by["sw-2"]["chapter"] == "1"   # the first by site order wins
assert by["sw-1"]["chapter"] == "0" and by["sw-1"]["kind"] == "chapter"
assert by["sw-9"]["kind"] == "extra" and by["sw-9"]["chapter"] == "Special Story" and by["sw-9"]["publishAt"] == ""
assert by["sw-8"]["title"] == "Oneshot" and by["sw-4"]["chapter"] == "2.5"
assert by["sw-5"]["publishAt"] == "2023-11-14T22:13:20+00:00", by["sw-5"]["publishAt"]
assert ms._sw_iso("junk") == "" and ms._sw_iso(None) == "" and ms._sw_iso(0) == ""

# ── 7. a series page as the panel gets it (through info(), which caches)
fake_gql({"fetchChapters": lambda v: {"fetchChapters": {"chapters": [ch(1, 1.0, "Chapter 1"), ch(2, 2.0, "Chapter 2", 1)]}},
          "fetchManga": lambda v: {"fetchManga": {"manga": mg(7, "Solo Leveling", status="ON_HIATUS")}}})
reset()
i = ms.info("sw-7")
assert i["id"] == "sw-7" and i["title"] == "Solo Leveling" and i["description"] == "A story.", i
assert i["authors"] == ["A. Writer", "B. Drawer"] and i["status"] == "On hiatus", i          # split, de-duplicated, in order
assert [c["id"] for c in i["chapters"]] == ["sw-1", "sw-2"] and i["image"].startswith("http://127.0.0.1:")
n = len(calls); ms.info("sw-7"); assert len(calls) == n                                      # info() caches once, not twice
ms._cache.pop("info:sw-7")                                                                   # what the favourites check does
ms.info("sw-7"); assert len(calls) > n                                                       # ...and it really refetches

# ── 8. pages: this server's links, never Suwayomi's; one page list per chapter
paths = ["/api/v1/manga/7/chapter/1/page/0", "/api/v1/manga/7/chapter/1/page/1", "https://other.example/p2.png"]
fake_gql({"fetchChapterPages": lambda v: {"fetchChapterPages": {"pages": list(paths)}}}); reset()
pg = ms._pages("sw-55")
assert [p["page"] for p in pg] == [1, 2, 3] and all("/swpage?c=sw-55&i=" in p["img"] for p in pg), pg
assert "/api/v1" not in pg[0]["img"]
fetched = []
def fake_raw(url, timeout=30):
    fetched.append((url, timeout)); return b"IMG", "image/webp"
ms._raw_get = fake_raw
assert ms.sw_page_bytes("sw-55", 0) == (b"IMG", "image/webp")
assert fetched[0] == ("http://127.0.0.1:4567/api/v1/manga/7/chapter/1/page/0", 60), fetched
ms.sw_page_bytes("sw-55", 2); assert fetched[1][0] == "https://other.example/p2.png"
ms.sw_page_bytes("sw-55", 0); assert len(fetched) == 2                                        # cached
n = len(calls); ms.sw_page_bytes("sw-55", 1); assert len(calls) == n                          # the page list is not asked again
try:
    ms.sw_page_bytes("sw-55", 9); raise SystemExit("page out of range accepted")
except IndexError:
    pass

# ── 9. a pick on one site never replaces the pick on another; a Suwayomi title opens with Suwayomi
ms.match_set("42", "01J76XYABC/Some-Series", "Some Series", True, 1.0)
ms.match_set("42", "sw-7", "Some Series", True, 1.0)
data = json.load(open(ms.MATCH_FILE))
assert data["42"]["id"] == "01J76XYABC/Some-Series" and data["42@suwayomi"]["id"] == "sw-7", data
assert ms.match_reverse("sw-7") == "42"
ms.provider_set("suwayomi"); ms.match_clear("42")
data = json.load(open(ms.MATCH_FILE)); assert "42" in data and "42@suwayomi" not in data, data
fake_gql({"sources": lambda v: {"sources": {"nodes": list(SOURCES)}}, "fetchSourceManga": by_source(table)}); reset()
m, cands = ms.al_match(al_media(7, english="Solo Leveling"))
assert m["id"] == "sw-1" and m["manual"] is False
assert json.load(open(ms.MATCH_FILE))["7@suwayomi"]["id"] == "sw-1"
assert ms.al_candidates("7", "solo")["results"][0]["id"] == "sw-1"                              # a typed search
ms.al_media = lambda aid: al_media(int(aid))
assert ms.al_candidates("7", "")["results"][0]["id"] == "sw-1"                                  # the automatic list
ms.provider_set("weebcentral")
ms.match_set("42", "sw-7", "Some Series", True, 1.0)                  # a saved title that came from Suwayomi
seen = {}
ms.al_detail = lambda aid, provider=None: seen.setdefault("p", provider) and {"id": "x", "chapters": []}
ms.info_for_ui("sw-7")
assert seen["p"] == "suwayomi", seen

# ── 10. downloads: Suwayomi pages go through sw_page_bytes
ms.sw_pages = lambda cid: [{"page": 1, "img": "x"}, {"page": 2, "img": "y"}]
ms.sw_page_bytes = lambda cid, i: (b"P" + bytes([i]), "image/webp" if i else "image/png")
ms._cache.clear()
ms.dl_start("sw-7", "sw-chdl", "1", "Chapter 1", "Solo Leveling", "")
for _ in range(100):
    if ms.dl_progress("sw-chdl").get("status") in ("done", "error"): break
    time.sleep(0.05)
assert ms.dl_progress("sw-chdl")["status"] == "done", ms.dl_progress("sw-chdl")
files = sorted(os.listdir(os.path.join(ms.DOWNLOADS_DIR, "sw-7", "sw-chdl")))
assert files == ["001.png", "002.webp", "meta.json"], files

# ── 11. the HTTP side
ms.sw_page_bytes = lambda cid, i: (b"PIXELS", "image/jpeg")
srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{port}"

def call(path, data=None, headers=None):
    req = urllib.request.Request(base + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers=headers or {})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers

st, body, h = call("/swpage?c=sw-55&i=0")
assert st == 200 and body == b"PIXELS" and h["Content-Type"] == "image/jpeg"
assert call("/swpage?c=55&i=0")[0] == 400 and call("/swpage?c=md-x&i=0")[0] == 400 and call("/swpage?c=sw-5&i=a")[0] == 400
st, body, _ = call("/provider", {"provider": "suwayomi"})
assert st == 200 and json.loads(body)["provider"] == "suwayomi"
ms.sw_latest = lambda page: {"results": [{"id": "sw-z"}], "hasMore": False, "nextPage": page + 1}
ms.sw_search = lambda q, offset=0: {"results": [{"id": "sw-q:" + q + str(offset)}], "hasMore": False, "nextOffset": offset + 20}
assert json.loads(call("/latest?page=1")[1])["results"][0]["id"] == "sw-z"
assert json.loads(call("/hot")[1])[0]["id"] == "sw-z"                                         # the "hot" list is the latest list
assert json.loads(call("/search?q=abc&offset=20")[1])["results"][0]["id"] == "sw-q:abc20"
call("/provider", {"provider": "weebcentral"})
srv.shutdown()

# ── 12. start and stop: a real child process
ms.sw_gql = lambda *a, **k: (_ for _ in ()).throw(AssertionError("no graphql here"))
def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split(")")[-1].split()[0] != "Z"          # a zombie is dead for our purposes
    except (OSError, FileNotFoundError):
        return False

def fresh():
    ms._sw_ok_until[0] = 0.0; ms._sw_proc = None

# nothing running and no command: the message says what to set
ms.SW_URL = f"http://127.0.0.1:{free_port()}"; ms.SW_CMD = ""; fresh()
try:
    ms.sw_ensure_up(); raise SystemExit("no error without a command")
except RuntimeError as e:
    assert "SEKAIPOP_SW_CMD" in str(e), e

# a command that dies: its exit code and the log path are in the error
ms.SW_CMD = "echo boom >&2; exit 3"; fresh()
try:
    ms.sw_ensure_up(wait=10); raise SystemExit("dead command accepted")
except RuntimeError as e:
    assert "code 3" in str(e) and ms.SW_LOG in str(e), e
assert "boom" in open(ms.SW_LOG).read()                                 # its output is kept, not thrown away

# a launcher that exits 0 and starts nothing: waits, then times out (it is not "crashed")
ms.SW_CMD = "exit 0"; fresh()
t0 = time.monotonic()
try:
    ms.sw_ensure_up(wait=1.5); raise SystemExit("timeout not raised")
except RuntimeError as e:
    assert "did not start" in str(e), e

# a real server: started on first use, found again (not started twice), the whole group ended on stop
port = free_port()
ms.SW_URL = f"http://127.0.0.1:{port}"
ms.SW_CMD = f"sleep 0; exec python3 -m http.server {port} --bind 127.0.0.1"   # `sleep 0;` keeps `sh` as the parent
fresh()
ms.sw_ensure_up(wait=20)
p = ms._sw_proc
assert p is not None and ms._sw_up() and alive(p.pid)
ms._sw_ok_until[0] = 0.0; ms.sw_ensure_up()
assert ms._sw_proc is p                                                  # already up: no second process
kids = [int(x) for x in os.popen(f"pgrep -g {p.pid}").read().split()]
assert len(kids) >= 1, kids
ms.sw_stop()
time.sleep(0.3)
assert not ms._sw_up() and not any(alive(k) for k in kids), kids        # every process of the group is gone
ms.sw_stop()                                                             # stopping twice is harmless

# one that was already running is adopted, and never stopped by us
ext = os.popen  # (a second server, started outside)
import subprocess
port2 = free_port()
outside = subprocess.Popen(["python3", "-m", "http.server", str(port2), "--bind", "127.0.0.1"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ms.SW_URL = f"http://127.0.0.1:{port2}"; ms.SW_CMD = "false"; fresh()
for _ in range(50):
    if ms._sw_up(): break
    time.sleep(0.1)
ms.sw_ensure_up()                                                        # up already: SW_CMD is never run
assert ms._sw_proc is None
ms.sw_stop(); assert outside.poll() is None                              # not ours: left alone
outside.send_signal(signal.SIGTERM); outside.wait(5)

# ── the launcher install-deps.sh writes is found without any env var
def load_fresh(env):
    saved = {k: os.environ.get(k) for k in ("XDG_DATA_HOME", "SEKAIPOP_SW_CMD", "SEKAIPOP_SW_URL")}
    for k in saved: os.environ.pop(k, None)
    os.environ.update(env)
    try:
        sp = importlib.util.spec_from_file_location("ms2", os.path.join(HERE, "..", "manga_server.py"))
        m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
    finally:
        for k, v in saved.items():
            if v is None: os.environ.pop(k, None)
            else: os.environ[k] = v
xdg = tempfile.mkdtemp(prefix="it's a dir ")                    # a quote in the path must survive the shell
os.makedirs(os.path.join(xdg, "suwayomi"))
run_sh = os.path.join(xdg, "suwayomi", "run.sh")
m0 = load_fresh({"XDG_DATA_HOME": xdg})
assert m0.SW_ENABLED is False and m0.SW_CMD == ""               # no launcher yet
open(run_sh, "w").write("#!/bin/sh\necho started\n")
m1 = load_fresh({"XDG_DATA_HOME": xdg})
assert m1.SW_ENABLED is False                                   # present but not executable: not used
os.chmod(run_sh, 0o755)
m2 = load_fresh({"XDG_DATA_HOME": xdg})
assert m2.SW_ENABLED is True and m2.SW_CMD
assert subprocess.run(m2.SW_CMD, shell=True, capture_output=True, text=True).stdout.strip() == "started"
m3 = load_fresh({"XDG_DATA_HOME": xdg, "SEKAIPOP_SW_URL": "http://127.0.0.1:4567"})
assert m3.SW_ENABLED is True and m3.SW_CMD == ""                # "already running" is never started for you
m4 = load_fresh({"XDG_DATA_HOME": xdg, "SEKAIPOP_SW_CMD": "echo mine"})
assert m4.SW_CMD == "echo mine"                                 # an explicit command wins

print("test_suwayomi: ok")
