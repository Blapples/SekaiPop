"""Browse by the source's own catalog (Popular / Latest / Highest rated / Most viewed), with every
site mocked: no network, no Suwayomi. Nothing in here may touch AniList.
Run: python3 tests/test_browse.py"""
import os, json, tempfile, threading, importlib.util, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["XDG_DATA_HOME"] = tempfile.mkdtemp()
os.environ.pop("SEKAIPOP_SW_CMD", None); os.environ.pop("SEKAIPOP_SW_URL", None)
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR = tmp
ms.PROVIDER_FILE = os.path.join(tmp, "provider.json")
ms.SW_LOG = os.path.join(tmp, "suwayomi.log")
ms.SW_ENABLED = True
ms._prov["v"] = None

def al_guard(*a, **k):
    raise AssertionError("browsing a source must not ask AniList")
ms._al_request = al_guard

# ── 1. WeebCentral: Popular = its own search by popularity, Latest = latest updates, nothing else
seen = []
def fake_search(q, mtype=None, offset=0, sort="Latest Updates"):
    seen.append((q, mtype, offset, sort))
    return {"results": [{"id": "A/Sol", "title": "Sol"}], "hasMore": True, "nextOffset": offset + 1}
LATEST = {"results": [{"id": "B/Moon", "title": "Moon", "chapter": "12"}], "hasMore": False, "nextPage": 2}
ms.search = fake_search
ms.latest_updates = lambda page=1: LATEST
ms.provider_set("weebcentral")
r = ms.source_browse("popular", 2)
assert seen == [("", None, ms.PAGE_LIMIT, "Popularity")], seen            # page 2 = the second page of 32
assert r["nextPage"] == 3 and r["hasMore"] is True and r["sorts"] == ["popular", "latest"], r
r = ms.source_browse("latest", 1)
assert r["results"][0]["chapter"] == "12" and r["sorts"] == ["popular", "latest"]
assert "sorts" not in LATEST                                              # the cached answer was copied, not changed
for bad in ("rating", "views"):
    try:
        ms.source_browse(bad); raise SystemExit("WeebCentral accepted " + bad)
    except ValueError:
        pass
assert ms.source_browse("nonsense")["sorts"] == ["popular", "latest"]    # an unknown sort means Popular
assert seen[-1][3] == "Popularity"

# ── 2. MangaDex: follows, newest chapter, rating; no view count to sort by
asked = []
def md_get(path, params=None, timeout=20):
    asked.append(dict((k, v) for k, v in params if k.startswith("order[") or k in ("offset", "limit")))
    return {"data": [{"id": "x1", "attributes": {"title": {"en": "Dex One"}, "updatedAt": "2026-01-01"},
                      "relationships": []}], "total": 100}
real_md_get = ms.md_get; ms.md_get = md_get
ms.provider_set("mangadex"); ms._cache.clear()
r = ms.source_browse("popular", 1)
assert asked[-1]["order[followedCount]"] == "desc" and asked[-1]["offset"] == 0, asked[-1]
assert r["results"][0]["id"] == "md-x1" and r["sorts"] == ["popular", "latest", "rating"] and r["hasMore"] is True
ms.source_browse("rating", 3)
assert asked[-1] == {"limit": ms.PAGE_LIMIT, "offset": 2 * ms.PAGE_LIMIT, "order[rating]": "desc"}, asked[-1]
ms.source_browse("latest", 1)
assert "order[latestUploadedChapter]" in asked[-1]
n = len(asked); ms.source_browse("rating", 3); assert len(asked) == n      # kept for a moment
try:
    ms.source_browse("views"); raise SystemExit("MangaDex accepted views")
except ValueError:
    pass
ms.md_get = real_md_get

# ── 3. Suwayomi: each source's own Popular / Latest; rating and views through its own sort filter
calls, lock = [], threading.Lock()
SOURCES = [
    {"id": "10", "name": "Alpha", "lang": "en", "supportsLatest": True,  "isNsfw": False},   # Sort filter
    {"id": "30", "name": "Zeta",  "lang": "en", "supportsLatest": True,  "isNsfw": False},   # "Order by" select
    {"id": "60", "name": "Plain", "lang": "en", "supportsLatest": False, "isNsfw": False},   # nothing to sort by
]
FILTERS = {
    "10": [{"__typename": "HeaderFilter"},
           {"__typename": "SortFilter", "name": "Sort by", "values": ["Alphabetical", "Latest", "Popularity", "Most Viewed", "Rating"]}],
    "30": [{"__typename": "SelectFilter", "name": "Order by", "values": ["Default", "A-Z", "Z-A", "Latest Update", "Highest rated"]}],
    "60": [{"__typename": "TextFilter"}],
}
def mg(i, t): return {"id": i, "title": t, "thumbnailUrl": f"/t/{i}", "status": "ONGOING", "genre": ["Action"],
                      "description": "", "author": "", "artist": ""}
def gql(query, variables=None, timeout=60):
    with lock: calls.append((query, variables))
    if "__type(" in query:
        return {"__type": {"fields": [{"name": "name"}, {"name": "values"}], "inputFields": None}}
    if "sources {" in query:
        return {"sources": {"nodes": list(SOURCES)}}
    if "filters" in query and "source(id:" in query:
        sid = query.split('source(id: "')[1].split('"')[0]
        return {"source": {"filters": FILTERS[sid]}}
    if "fetchSourceManga" in query:
        i = variables["input"]
        return {"fetchSourceManga": {"hasNextPage": True, "mangas": [mg(int(i["source"]) + 1, "T" + i["source"])]}}
    raise AssertionError(query[:50])
ms.sw_gql = gql
ms.provider_set("suwayomi")
def fetches(): return [v["input"] for q, v in calls if "fetchSourceManga" in q]
def reset(focus=""):
    ms._cache.clear(); ms._sw_types.clear(); calls.clear(); ms._sw_focus["id"] = focus

reset("10")
r = ms.source_browse("popular", 2)
f = fetches(); assert f == [{"source": "10", "type": "POPULAR", "page": 2}], f          # its own feed, no query, no filters
assert r["sorts"] == ["popular", "latest", "rating", "views"] and r["results"][0]["id"] == "sw-11" and r["nextPage"] == 3, r
assert r["results"][0]["type"] == "Alpha"
calls.clear(); ms.source_browse("latest", 1)
assert fetches() == [{"source": "10", "type": "LATEST", "page": 1}]
calls.clear(); ms.source_browse("rating", 1)
assert fetches() == [{"source": "10", "type": "SEARCH", "page": 1, "query": "",
                      "filters": [{"position": 1, "sortState": {"index": 4, "ascending": False}}]}], fetches()
calls.clear(); ms.source_browse("views", 1)
assert fetches()[0]["filters"] == [{"position": 1, "sortState": {"index": 3, "ascending": False}}]
n = len([1 for q, v in calls if "source(id:" in q]); ms.source_browse("rating", 2)
assert len([1 for q, v in calls if "source(id:" in q]) == n                              # filters read once per source

reset("30")                                                                              # an "Order by" select
r = ms.source_browse("rating", 1)
assert fetches() == [{"source": "30", "type": "SEARCH", "page": 1, "query": "",
                      "filters": [{"position": 0, "selectState": 4}]}], fetches()
try:
    ms.source_browse("views"); raise SystemExit("a source with no view sort was asked for views")
except ValueError as e:
    assert "views" in str(e)
assert ms.source_browse("popular")["sorts"] == ["popular", "latest", "rating"]

reset("60")                                                                              # no latest, no sorts
assert ms.source_browse("popular")["sorts"] == ["popular"]
assert ms.source_browse("latest")["results"] == []                                       # asks nobody, says nothing found

reset("")                                                                                # all picked sources at once
ms.source_browse("views")
assert [i["source"] for i in fetches()] == ["10"]                                        # only the one that can
reset("")
r = ms.source_browse("popular")
assert {i["source"] for i in fetches()} == {"10", "30", "60"} and all(i["type"] == "POPULAR" for i in fetches())

# Suwayomi will not describe its filters (older / different schema): Popular and Latest still work
def gql_plain(query, variables=None, timeout=60):
    if "__type(" in query:
        raise RuntimeError("introspection off")
    return gql(query, variables, timeout)
ms.sw_gql = gql_plain; reset("10")
assert ms.source_browse("popular")["sorts"] == ["popular", "latest"]
try:
    ms.source_browse("rating"); raise SystemExit("rating offered without filters")
except ValueError:
    pass
ms.sw_gql = gql

# picking other sources drops what was learned about the old ones
reset("10"); ms.source_browse("popular"); ms._sw_forget()
assert not [k for k in ms._cache if k.startswith(("swbrowse:", "sw:sorts:"))]

# ── 4. the route: /browse answers, a sort the source lacks is a 400 with the reason, never AniList
srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_address[1]}"
def get(path):
    try:
        with urllib.request.urlopen(base + path, timeout=10) as r: return r.status, json.load(r)
    except urllib.error.HTTPError as e: return e.code, json.load(e)
ms.provider_set("mangadex"); ms.md_get = md_get; ms._cache.clear()
st, d = get("/browse?sort=rating&page=1"); assert st == 200 and d["sorts"] == ["popular", "latest", "rating"], (st, d)
st, d = get("/browse?sort=views"); assert st == 400 and "views" in d["error"], (st, d)
st, d = get("/browse"); assert st == 200 and asked[-1].get("order[followedCount]") == "desc"   # Popular is the default
st, d = get("/browse?page=x"); assert st == 400, (st, d)
srv.shutdown()
print("browse: all ok")
