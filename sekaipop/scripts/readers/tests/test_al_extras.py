"""The profile page's extra AniList questions: the type / decade mix (from the list), the profile
colour, tags and staff, the activity feed, and the recommendations, with AniList mocked. Each part is
optional: a part AniList refuses is left out and the others still answer.
Run: python3 tests/test_al_extras.py"""
import os, sys, json, time, base64, tempfile, importlib.util, threading, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR = tmp
ms.AL_AUTH_FILE = os.path.join(tmp, "anilist_auth.json")

def jwt(exp):
    b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
    return b({"alg": "none"}) + "." + b({"exp": exp}) + "." + "sig" * 8
GOOD = jwt(int(time.time()) + 86400 * 300)
NOW = int(time.time())

_id = [0]
def entry(mid, status, title, score100=0, country="JP", fmt="MANGA", year=2020, progress=0):
    _id[0] += 1
    return {"id": _id[0], "status": status, "score": score100 / 10, "score100": score100,
            "progress": progress, "progressVolumes": 0, "updatedAt": NOW, "createdAt": 1,
            "media": {"id": mid, "title": {"english": title, "romaji": title, "native": None},
                      "coverImage": {"large": f"https://img/{mid}.jpg"}, "format": fmt,
                      "status": "RELEASING", "chapters": 0, "volumes": 0, "genres": [],
                      "countryOfOrigin": country, "startDate": {"year": year}, "averageScore": 80, "tags": []}}

ENTRIES = [
    entry(1, "CURRENT",   "Alpha",   90, "JP", "MANGA", 2021),
    entry(2, "COMPLETED", "Beta",    80, "KR", "MANGA", 2015),
    entry(3, "COMPLETED", "Gamma",   75, "CN", "MANGA", 2008),
    entry(4, "COMPLETED", "Delta",    0, "JP", "ONE_SHOT", 1975),
    entry(5, "DROPPED",   "Epsilon", 40, "JP", "MANGA", 2023),
    entry(6, "PLANNING",  "Zeta",     0, "KR", "MANGA", 2024),      # planning is not part of the mix
    entry(7, "COMPLETED", "NoYear",  70, "JP", "MANGA", 0),
]

def rec(mid, title, rating, fmt="MANGA", avg=80):
    return {"rating": rating, "mediaRecommendation": {
        "id": mid, "title": {"english": title, "romaji": title, "native": None},
        "coverImage": {"large": f"https://img/{mid}.jpg"}, "format": fmt, "status": "FINISHED",
        "startDate": {"year": 2019}, "averageScore": avg, "genres": [], "countryOfOrigin": "JP"}}

RECS = {   # source media id -> recommendation nodes
    1: [rec(101, "Rec A", 50), rec(102, "Rec B", 40), rec(103, "Rec C", 30), rec(2, "Owned Beta", 99),
        rec(104, "Negative", -3), rec(105, "A Novel", 20, fmt="NOVEL"),
        rec(106, "Rec G", 20), rec(107, "Rec H", 15)],
    2: [rec(101, "Rec A", 70), rec(201, "Rec D", 60), rec(202, "Rec E", 55), rec(203, "Rec F", 54)],
    3: [rec(301, "Lonely", 10)],
}
state = {"stats": "ok", "feed": "ok", "recs": "ok", "asked": []}
BASE_FEED = [
    {"createdAt": NOW - 7200, "status": "read chapter", "progress": "52",
     "media": {"id": 1, "title": {"english": "Alpha", "romaji": "Alpha", "native": None}, "coverImage": {"large": "https://img/1.jpg"}}},
    {},                                                                     # an activity of another kind
    {"createdAt": NOW - 90000, "status": "completed", "progress": None,
     "media": {"id": 2, "title": {"english": "Beta", "romaji": "Beta", "native": None}, "coverImage": {"large": "https://img/2.jpg"}}},
    {"createdAt": NOW - 99999, "status": "plans to read", "progress": None, "media": None},    # no media: skipped
]

def fake_request(query, variables, token=None):
    assert token == GOOD
    state["asked"].append(query.split("(")[0].strip()[:40])
    if "MediaListCollection" in query:
        lists = {}
        for e in ENTRIES:
            lists.setdefault(e["status"], []).append(e)
        return {"MediaListCollection": {"hasNextChunk": False, "lists": [
            {"status": s, "isCustomList": False, "entries": es} for s, es in lists.items()]}}
    if "profileColor" in query:
        if state["stats"] == "fail":
            raise RuntimeError("Cannot query field \"tags\" on type \"UserStatistics\"")
        return {"Viewer": {"options": {"profileColor": "purple"},
            "statistics": {"manga": {
                "tags": [{"tag": {"name": "Romance"}, "count": 30, "meanScore": 81.5},
                         {"tag": {"name": ""}, "count": 99, "meanScore": 1},
                         {"tag": {"name": "Drama"}, "count": 12, "meanScore": 0}],
                "staff": [{"staff": {"id": 7, "name": {"full": "Some Author"}, "siteUrl": "https://anilist.co/staff/7"}, "count": 9, "meanScore": 85},
                          {"staff": {"id": 8, "name": {"full": "Odd Link"}, "siteUrl": "javascript:alert(1)"}, "count": 4, "meanScore": 70},
                          {"staff": {"id": None, "name": {"full": "No Id"}}, "count": 1}]}}}}
    if "ListActivity" in query:
        if state["feed"] == "fail":
            raise RuntimeError("boom")
        return {"Page": {"activities": BASE_FEED}}
    if "recommendations(" in query:
        if state["recs"] == "fail":
            raise RuntimeError("boom")
        state["recs_ids"] = list(variables["ids"])
        return {"Page": {"media": [{"id": i, "recommendations": {"nodes": RECS.get(i, [])}}
                                   for i in variables["ids"]]}}
    raise AssertionError(query)
ms._al_request = fake_request

srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
ms.PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{ms.PORT}"

def call(path, headers=None):
    req = urllib.request.Request(BASE + path, headers=headers or {})
    try:
        r = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        r = e
    return (r.status if hasattr(r, "status") else r.code), json.loads(r.read()), r.headers

def fresh():
    for k in ("al:list:", "al:extras:", "al:feed:", "al:recs:"):
        ms._cache_drop(k)

# ── logged out: 401 and AniList not asked
for path in ("/al/extras", "/al/recs"):
    assert call(path)[0] == 401, path
assert not state["asked"]
ms._auth_write({"token": GOOD, "expiresAt": NOW + 86400,
                "viewer": {"id": 42, "name": "V", "scoreFormat": "POINT_10"}})

# ── the mix: read titles only, by type and by decade
j = ms.al_overview()
types = {t["label"]: t["count"] for t in j["mix"]["types"]}
assert types == {"MANGA": 3, "MANHWA": 1, "MANHUA": 1, "ONE-SHOT": 1}, types      # Zeta (planning) is not counted
assert j["mix"]["types"][0]["label"] == "MANGA", "most first"
dec = j["mix"]["decades"]
assert [d["label"] for d in dec] == ["2020s", "2010s", "2000s", "Before 1990"], dec
assert [d["count"] for d in dec] == [2, 1, 1, 1], dec          # Alpha + Epsilon; Beta; Gamma; Delta. NoYear has none

# ── extras: colour, tags, staff, feed
fresh()
st, j, h = call("/al/extras")
assert st == 200 and h.get("Access-Control-Allow-Origin") is None
assert j["color"] == "#c063ff"
assert [t["label"] for t in j["tags"]] == ["Romance", "Drama"], j["tags"]
assert j["tags"][0] == {"label": "Romance", "count": 30, "meanScore": 81.5}
assert [s["label"] for s in j["staff"]] == ["Some Author", "Odd Link"], j["staff"]
assert j["staff"][0]["url"] == "https://anilist.co/staff/7"
assert j["staff"][1]["url"] == "https://anilist.co/staff/8", "a link that is not AniList's is rebuilt from the id"
assert [f["title"] for f in j["feed"]] == ["Alpha", "Beta"], j["feed"]
f0 = j["feed"][0]
assert f0["id"] == "al:1" and f0["status"] == "read chapter" and f0["progress"] == "52" and f0["createdAt"] == NOW - 7200
assert j["feed"][1]["progress"] == "" and f0["image"], "the cover goes through the image proxy"

# ── kept for a while: asking again does not ask AniList again
n = len(state["asked"])
call("/al/extras")
assert len(state["asked"]) == n

# ── a refused part is left out; the others answer
fresh(); state["stats"] = "fail"
st, j, _h = call("/al/extras")
assert st == 200 and j["color"] == "" and j["tags"] == [] and j["staff"] == [] and len(j["feed"]) == 2, j
fresh(); state["stats"] = "ok"; state["feed"] = "fail"
st, j, _h = call("/al/extras")
assert st == 200 and j["feed"] == [] and j["tags"] and j["color"] == "#c063ff"
state["feed"] = "ok"

# ── profile colours
assert ms._al_profile_color("Blue") == "#3db4f2" and ms._al_profile_color("#AABBCC") == "#aabbcc"
assert ms._al_profile_color("chartreuse") == "" and ms._al_profile_color(None) == "" and ms._al_profile_color("#12345") == ""

# ── recommendations: from the top scored titles, never what is already listed, once each, by shelf
fresh()
st, j, _h = call("/al/recs")
assert st == 200
assert state["recs_ids"] == [1, 2, 3, 7], state["recs_ids"]      # by score; Epsilon (40) is under the minimum
g = j["groups"]
assert [x["because"] for x in g] == ["Alpha", "Beta"], g       # Gamma has one recommendation: not a shelf
alpha = [c["title"] for c in g[0]["items"]]
beta  = [c["title"] for c in g[1]["items"]]
assert alpha == ["Rec B", "Rec C", "Rec G", "Rec H"], alpha
assert "Rec A" not in alpha and "Rec A" in beta, "Rec A is under the source whose readers rated it highest"
assert "Owned Beta" not in alpha + beta and "Negative" not in alpha and "A Novel" not in alpha
assert beta[0] == "Rec A" and set(beta) == {"Rec A", "Rec D", "Rec E", "Rec F"}, beta
c0 = g[1]["items"][0]
assert c0["id"] == "al:101" and c0["avg"] == 80 and c0["rating"] == 70 and c0["image"] and g[1]["becauseId"] == "al:2"

# ── a failed recommendations question is an empty answer, not an error
fresh(); state["recs"] = "fail"
st, j, _h = call("/al/recs")
assert st == 200 and j == {"groups": []}
state["recs"] = "ok"

# ── nothing scored high enough: no question is asked
fresh(); saved = list(ENTRIES); ENTRIES[:] = [e for e in ENTRIES if e["score100"] < 70]
state["asked"].clear()
assert call("/al/recs")[1] == {"groups": []}
assert not any(q.startswith("query ($ids") for q in state["asked"]), state["asked"]
ENTRIES[:] = saved

# ── the panel only
for path in ("/al/extras", "/al/recs"):
    assert call(path, {"Origin": "https://evil.example"})[0] == 403, path
    assert call(path, {"Host": "evil.example"})[0] == 403, path
print("ok")
