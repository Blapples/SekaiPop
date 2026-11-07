"""The MangaDex provider, with MangaDex mocked (no network).
Run: python3 tests/test_mangadex.py"""
import os, json, tempfile, threading, importlib.util
import urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)
real_md_get = ms.md_get

tmp = tempfile.mkdtemp()
ms.DATA_DIR       = tmp
ms.MATCH_FILE     = os.path.join(tmp, "anilist_matches.json")
ms.PROVIDER_FILE  = os.path.join(tmp, "provider.json")
ms.DOWNLOADS_DIR  = os.path.join(tmp, "downloads"); os.makedirs(ms.DOWNLOADS_DIR)
ms.FAVORITES_FILE = os.path.join(tmp, "favorites.json")
ms.MD_MIN_GAP     = 0

UUID  = "11111111-1111-1111-1111-111111111111"
UUID2 = "22222222-2222-2222-2222-222222222222"


def manga(uid, title, alts=(), year=2020, al=None, cover="c.jpg", status="ongoing"):
    return {"id": uid, "type": "manga",
            "attributes": {"title": {"en": title}, "altTitles": [{"ja-ro": a} for a in alts],
                           "year": year, "status": status, "links": ({"al": al} if al else {}),
                           "description": {"en": "A story.\n\n---\n**Translator note** [x](http://x)"},
                           "tags": [{"attributes": {"name": {"en": "Action"}}}],
                           "updatedAt": "2026-11-01T00:00:00+00:00"},
            "relationships": [{"type": "cover_art", "id": "cv", "attributes": {"fileName": cover}},
                              {"type": "author", "id": "a1", "attributes": {"name": "Some Author"}}]}


def chap(uid, num, pages=10, when="2020-01-01T00:00:00+00:00", title=None, ext=None):
    return {"id": uid, "type": "chapter",
            "attributes": {"chapter": num, "title": title, "pages": pages, "publishAt": when,
                           "externalUrl": ext, "translatedLanguage": "en"}}


calls = []


def fake_md(routes):
    """routes: {path-prefix: fn(params dict) -> json}; every call is logged."""
    def md_get(path, params=None, timeout=20):
        calls.append((path, list(params or [])))
        for prefix, fn in routes.items():
            if path.startswith(prefix):
                return fn(dict(params or []) , list(params or []))
        raise AssertionError("unexpected " + path)
    ms.md_get = md_get


# ── 1. provider: WeebCentral by default, the choice is kept, a bad name is refused
assert ms.provider_get() == "weebcentral"
st = ms.provider_set("mangadex")
assert st["provider"] == "mangadex" and st["label"] == "MangaDex" and len(st["providers"]) == 2
ms._prov["v"] = None                                             # as after a restart
assert ms.provider_get() == "mangadex"
try:
    ms.provider_set("nope"); raise SystemExit("bad provider accepted")
except ValueError:
    pass
assert ms.is_md("md-" + UUID) and not ms.is_md("01J76XYABC/Some-Series")

# ── 2. search rows: prefixed id, proxied 512 px cover, AniList link, tags
fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "Solo Leveling", al="105398")], "total": 1}})
r = ms.md_search("solo")
row = r["results"][0]
assert row["id"] == "md-" + UUID and row["al"] == "105398" and row["year"] == "2020", row
assert "uploads.mangadex.org%2Fcovers%2F" + UUID in row["image"] and "c.jpg.512.jpg" in row["image"].replace("%2F", "/"), row
assert row["status"] == "Ongoing" and row["tags"] == ["Action"] and r["hasMore"] is False
sent = calls[-1][1]
assert ("availableTranslatedLanguage[]", "en") in sent and ("contentRating[]", "pornographic") in sent, sent

# ── 3. matching: MangaDex's own AniList link is an exact match, whatever the title says
def al_media(aid=105398, english="Solo Leveling", romaji="Na Honjaman Level-Up", native=None, syn=()):
    return {"id": aid, "title": {"english": english, "romaji": romaji, "native": native},
            "synonyms": list(syn), "startDate": {"year": 2018}, "countryOfOrigin": "KR"}


fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "Totally Different Name", al="105398"),
                                          manga(UUID2, "Solo Leveling", al="999")], "total": 2}})
c = ms.md_candidates(al_media())
assert c[0]["id"] == "md-" + UUID and c[0]["score"] == 1.0 and c[0]["via"] == "anilist", c
assert c[1]["score"] < 1.0 or c[1]["id"] != c[0]["id"]

# no link: the name decides, and another name of the series counts (capped, a shared name is not proof)
fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "Boku no Hero", alts=["The Perks of Being an S-Class Heroine"], year=2022)], "total": 1}})
c = ms.md_candidates(al_media(9, english="The Perks of Being an S-Class Heroine", romaji=None))
assert c and c[0]["score"] >= ms.MATCH_MIN and c[0]["score"] <= 1.0 and c[0]["via"] == "alias", c

# nothing alike: below the bar, so the panel asks the user to pick
fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "Cooking With Cats")], "total": 1}})
c = ms.md_candidates(al_media(10, english="Berserk", romaji="Berserk"))
assert c and c[0]["score"] < ms.MATCH_MIN, c

# the API failing is an error, not "no match"
def boom(p, l): raise RuntimeError("down")
fake_md({"/manga": boom})
try:
    ms.md_candidates(al_media(11)); raise SystemExit("error swallowed")
except RuntimeError:
    pass

# ── 4. chapters: one per number, the fullest upload wins, no external or empty ones
feed = [
    chap("c1", "1"), chap("c2", "2", pages=5), chap("c2b", "2", pages=18),            # c2b is fuller
    chap("c10", "10", when="2021-01-01T00:00:00+00:00"), chap("c2_5", "2.5"),
    chap("cx", "3", ext="https://mangaplus.shueisha.co.jp/x"), chap("c0", "4", pages=0),
    chap("one", None, title="Oneshot Special", when="2022-01-01T00:00:00+00:00"),
    chap("c3", "3", title="The Name of This One"),
]
out = ms._md_dedupe(feed)
ids = [c["id"] for c in out]
assert ids == ["md-c1", "md-c2b", "md-c2_5", "md-c3", "md-c10", "md-one"], ids
assert [c["index"] for c in out] == list(range(6))
byid = {c["id"]: c for c in out}
assert byid["md-c1"]["title"] == "Chapter 1" and byid["md-c1"]["kind"] == "chapter"
assert byid["md-c3"]["title"] == "The Name of This One" and byid["md-c3"]["chapter"] == "3"
assert byid["md-one"]["kind"] == "extra" and byid["md-one"]["chapter"] == "Oneshot Special"

# the feed is read in pages of 500 until the total is reached
n = {"calls": 0}
def feed_page(p, l):
    n["calls"] += 1
    off = int(p["offset"])
    data = [chap(f"x{off + i}", str(off + i + 1)) for i in range(500 if off == 0 else 100)]
    return {"data": data, "total": 600}
fake_md({"/manga/" + UUID + "/feed": feed_page})
chs = ms._md_chapters(UUID)
assert n["calls"] == 2 and len(chs) == 600 and chs[-1]["chapter"] == "600", (n, len(chs))
sent = dict(calls[-1][1])
assert sent["includeExternalUrl"] == 0 and sent["includeEmptyPages"] == 0 and sent["order[chapter]"] == "asc"

# ── 5. a whole series page, as the panel gets it
def series_routes():
    return {"/manga/" + UUID + "/feed": lambda p, l: {"data": [chap("c1", "1"), chap("c2", "2")], "total": 2},
            "/manga/" + UUID: lambda p, l: {"data": manga(UUID, "Solo Leveling")}}
fake_md(series_routes())
ms._cache.clear()
i = ms.info("md-" + UUID)                                      # info() sends md- ids to MangaDex
assert i["id"] == "md-" + UUID and i["title"] == "Solo Leveling" and i["authors"] == ["Some Author"], i
assert i["description"] == "A story." and i["status"] == "Ongoing" and len(i["chapters"]) == 2, i
assert i["image"].startswith("http://127.0.0.1:") and i["chapters"][0]["id"] == "md-c1"

# ── 6. latest updates
fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "A"), manga(UUID2, "B")], "total": 100}})
ms._cache.clear()
lt = ms.md_latest(2)
assert [x["id"] for x in lt["results"]] == ["md-" + UUID, "md-" + UUID2] and lt["hasMore"] and lt["nextPage"] == 3
assert ("order[latestUploadedChapter]", "desc") in calls[-1][1] and ("offset", ms.PAGE_LIMIT) in calls[-1][1]

# ── 7. pages: the panel gets links of this server, never a MangaDex token
home = {"baseUrl": "https://node1.mangadex.network:443/TOKEN1",
        "chapter": {"hash": "HASH", "data": ["1-a.png", "2-b.jpg", "3-c.jpg"], "dataSaver": ["1-a.jpg", "2-b.jpg", "3-c.jpg"]}}
home2 = {**home, "baseUrl": "https://node2.mangadex.network:443/TOKEN2"}
served = [home, home2]
fake_md({"/at-home/server/": lambda p, l: served.pop(0)})
ms._cache.clear()
pg = ms._pages("md-ch1")
assert [p["page"] for p in pg] == [1, 2, 3], pg
assert all("/mdpage?c=md-ch1&i=" in p["img"] and "TOKEN" not in p["img"] for p in pg), pg

# a page: first server fails, a fresh one is asked for, and the page is then served from cache
fetched = []
def fake_raw(url, timeout=30):
    fetched.append(url)
    if "node1" in url:
        raise RuntimeError("node1 is down")
    return b"IMG", "image/png"
reports = []
ms._raw_get = fake_raw
ms._md_report = lambda url, ok, nbytes, started: reports.append((url, ok))
ms._img_cache.clear()
body, ctype = ms.md_page_bytes("md-ch1", 0)
assert body == b"IMG" and ctype == "image/png"
assert fetched == ["https://node1.mangadex.network:443/TOKEN1/data/HASH/1-a.png",
                   "https://node2.mangadex.network:443/TOKEN2/data/HASH/1-a.png"], fetched
assert [ok for _, ok in reports] == [False, True]
ms.md_page_bytes("md-ch1", 0)
assert len(fetched) == 2                                          # cached, nothing fetched again
try:
    ms.md_page_bytes("md-ch1", 7); raise SystemExit("page out of range accepted")
except IndexError:
    pass

# ── 8. a rate limit is waited out once; the wait is read from seconds or from a unix time
import time as _t
assert ms._retry_after({"Retry-After": "2"}) == 2.0
assert ms._retry_after({"Retry-After": str(_t.time() + 3)}) <= 5.0
assert ms._retry_after({}) == 1.0 and ms._retry_after({"Retry-After": "x"}) == 1.0

class FakeResp:
    def __init__(self, code, body=None, headers=None): self.status_code, self._b, self.headers = code, body, headers or {}
    def raise_for_status(self):
        if self.status_code >= 400: raise RuntimeError(f"HTTP {self.status_code}")
    def json(self): return self._b
replies = [FakeResp(429, headers={"Retry-After": "0"}), FakeResp(200, {"ok": 1})]
sleeps = []
real_sleep = ms.time.sleep
ms.md_get = real_md_get
ms._get = lambda url, headers, timeout: replies.pop(0)
ms.time.sleep = lambda s: sleeps.append(s)
assert ms.md_get("/x") == {"ok": 1} and len(sleeps) == 1 and 0.5 <= sleeps[0] <= 5.0, sleeps
replies[:] = [FakeResp(429), FakeResp(429)]
try:
    ms.md_get("/x"); raise SystemExit("second 429 not raised")
except RuntimeError:
    pass
ms.time.sleep = real_sleep

# ── 9. a pick on one site never replaces the pick on the other
ms.match_set("42", "01J76XYABC/Some-Series", "Some Series", True, 1.0)
ms.match_set("42", "md-" + UUID, "Some Series", True, 1.0)
data = json.load(open(ms.MATCH_FILE))
assert data["42"]["id"] == "01J76XYABC/Some-Series" and data["42@mangadex"]["id"] == "md-" + UUID, data
assert ms.match_reverse("md-" + UUID) == "42" and ms.match_reverse("01J76XYABC/Some-Series") == "42"
ms.provider_set("mangadex")
ms.match_clear("42")                                              # clears the active site's pick only
data = json.load(open(ms.MATCH_FILE))
assert "42" in data and "42@mangadex" not in data, data
# a file written before providers existed (plain AniList ids only) still reads as WeebCentral's
ms.provider_set("weebcentral")
m, _ = ms.al_match(al_media(42))
assert m and m["id"] == "01J76XYABC/Some-Series" and m["manual"] is True

# al_match on MangaDex stores a good match under its own key
ms.provider_set("mangadex")
fake_md({"/manga": lambda p, l: {"data": [manga(UUID2, "Berserk", al="7")], "total": 1}})
m, cands = ms.al_match(al_media(7, english="Berserk", romaji="Berserk"))
assert m["id"] == "md-" + UUID2 and m["manual"] is False
assert json.load(open(ms.MATCH_FILE))["7@mangadex"]["id"] == "md-" + UUID2

# al_candidates follows the active provider (a typed search, and the automatic list)
fake_md({"/manga": lambda p, l: {"data": [manga(UUID, "Typed Result")], "total": 1}})
assert ms.al_candidates("7", "typed")["results"][0]["id"] == "md-" + UUID
ms.al_media = lambda aid: al_media(int(aid), english="Typed Result", romaji="Typed Result")
assert ms.al_candidates("7", "")["results"][0]["id"] == "md-" + UUID

# ── 10. a MangaDex title opens with MangaDex even while WeebCentral is the picked site
ms.provider_set("weebcentral")
fake_md({**series_routes(), "/manga": lambda p, l: {"data": [manga(UUID, "Solo Leveling")], "total": 1}})
seen = {}
ms.al_detail = lambda aid, provider=None: seen.setdefault("p", provider) and {"id": "x", "chapters": []}
ms.info_for_ui("md-" + UUID2)                                      # matched above to AniList 7
assert seen["p"] == "mangadex", seen

# ── 11. downloads: MangaDex pages go through md_page_bytes
ms.md_pages = lambda cid: [{"page": 1, "img": "x"}, {"page": 2, "img": "y"}]
ms.md_page_bytes = lambda cid, i: (b"P" + bytes([i]), "image/webp" if i else "image/png")
ms._cache.clear()
ms.dl_start("md-" + UUID, "md-chdl", "1", "Chapter 1", "Solo Leveling", "")
for _ in range(100):
    if ms.dl_progress("md-chdl").get("status") in ("done", "error"): break
    _t.sleep(0.05)
assert ms.dl_progress("md-chdl")["status"] == "done", ms.dl_progress("md-chdl")
files = sorted(os.listdir(os.path.join(ms.DOWNLOADS_DIR, "md-" + UUID, "md-chdl")))
assert files == ["001.png", "002.webp", "meta.json"], files
assert [p["img"].endswith(("001.png", "002.webp")) for p in ms.dl_pages("md-chdl")] == [True, True]

# ── 12. the HTTP side: /provider answers the panel only, /mdpage serves the image
ms.md_page_bytes = lambda cid, i: (b"PIXELS", "image/jpeg")
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

st, body, _ = call("/provider")
assert st == 200 and json.loads(body)["provider"] == "weebcentral"
st, body, _ = call("/provider", {"provider": "mangadex"})
assert st == 200 and json.loads(body)["provider"] == "mangadex" and ms.provider_get() == "mangadex"
st, body, _ = call("/provider", {"provider": "nope"})
assert st == 500 and "unknown provider" in json.loads(body)["error"]
st, _, _ = call("/provider", {"provider": "weebcentral"}, {"Origin": "http://evil.example"})
assert st == 403 and ms.provider_get() == "mangadex"               # another web page cannot switch it
st, body, h = call("/mdpage?c=md-" + UUID + "&i=0")
assert st == 200 and body == b"PIXELS" and h["Content-Type"] == "image/jpeg"
assert call("/mdpage?c=" + UUID + "&i=0")[0] == 400                # not a MangaDex id
assert call("/mdpage?c=md-x&i=a")[0] == 400
# /latest follows the provider
ms.md_latest = lambda page: {"results": [{"id": "md-z"}], "hasMore": False, "nextPage": page + 1}
assert json.loads(call("/latest?page=1")[1])["results"][0]["id"] == "md-z"
srv.shutdown()

print("test_mangadex: ok")
