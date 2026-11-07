"""The user's own AniList lists (the Library's Reading / Completed / Dropped / Planning tabs):
one status at a time, its filters and sorts, the size of every status, the chunks of a big
list, the copy kept for a minute and dropped by a save, and the login every route needs,
with AniList mocked.
Run: python3 tests/test_al_list.py"""
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

_id = [0]
def entry(mid, status, title, score100=0, progress=0, chapters=0, fmt="MANGA", country="JP",
          genres=(), tags=(), year=2020, mstatus="FINISHED", updated=0, created=0, score=None, vols=0, pv=0):
    _id[0] += 1
    return {"id": _id[0], "status": status, "score": score100 / 10 if score is None else score,
            "score100": score100, "progress": progress, "progressVolumes": pv,
            "updatedAt": updated, "createdAt": created,
            "media": {"id": mid, "title": {"english": title, "romaji": title + " (romaji)", "native": None},
                      "coverImage": {"large": f"https://img/{mid}.jpg"}, "format": fmt, "status": mstatus,
                      "chapters": chapters, "volumes": vols, "genres": list(genres), "countryOfOrigin": country,
                      "startDate": {"year": year}, "averageScore": 80, "tags": [{"name": t} for t in tags]}}

ENTRIES = [
    entry(1, "CURRENT",   "Blue Lock",       100, 322, 0,   genres=["Sports"], tags=["Football"], year=2018, mstatus="RELEASING", updated=50, created=5),
    entry(2, "CURRENT",   "Sasayaku",        100, 28,  0,   genres=["Romance"], year=2019, updated=40, created=6),
    entry(3, "CURRENT",   "Watashi no",       80, 23,  0,   genres=["Romance", "Drama"], tags=["Marriage"], year=2021, updated=60, created=7),
    entry(4, "CURRENT",   "Ao no Hako",        0, 164, 250, genres=["Romance", "Sports"], year=2021, updated=10, created=8, vols=28),
    entry(5, "CURRENT",   "Bocchi the Rock!", 70, 21,  0,   genres=["Comedy"], year=2018, updated=30, created=9),
    entry(6, "COMPLETED", "Solo Leveling",    90, 200, 200, country="KR", genres=["Action"], year=2018, updated=20, created=1),
    entry(7, "COMPLETED", "One Shot Thing",   60, 1,   1,   fmt="ONE_SHOT", year=2010, updated=21, created=2),
    entry(8, "DROPPED",   "Chainsaw Man",     50, 113, 232, genres=["Action"], year=2018, updated=5, created=3),
    entry(9, "PLANNING",  "Ring Ring",         0, 0,   0,   fmt="NOVEL", year=2022, created=4),
    entry(10, "PAUSED",   "On Hold",          60, 3,   0,   year=2015),
]
CUSTOM = {"status": None, "isCustomList": True, "entries": [ENTRIES[0], ENTRIES[5]]}

calls = []
revoked = {"on": False}
def fake_request(query, variables, token=None):
    if revoked["on"]:
        raise ms.AniListAuthError("Your AniList login has run out. Log in again.")
    assert token == GOOD, "the list is the user's own: asked as the logged-in user"
    if query.lstrip().startswith("mutation"):
        return {"SaveMediaListEntry": {"id": 1, "status": "CURRENT", "progress": 1, "progressVolumes": 0}}
    assert "MediaListCollection" in query and variables["uid"] == 42
    calls.append(variables["chunk"])
    # a small chunk size so the chunking is really used: 4 entries per chunk, one status list may
    # be cut across two chunks
    per = 4
    part = ENTRIES[(variables["chunk"] - 1) * per: variables["chunk"] * per]
    lists = {}
    for e in part:
        lists.setdefault(e["status"], []).append(e)
    out = [{"status": s, "isCustomList": False, "entries": es} for s, es in lists.items()]
    if variables["chunk"] == 1:
        out.append(CUSTOM)
    return {"MediaListCollection": {"hasNextChunk": variables["chunk"] * per < len(ENTRIES), "lists": out}}
ms._al_request = fake_request

srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
ms.PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{ms.PORT}"

def call(path, body=None, headers=None):
    req = urllib.request.Request(BASE + path, method="POST" if body is not None else "GET",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers or {})
    try:
        r = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        r = e
    raw = r.read()
    return (r.status if hasattr(r, "status") else r.code), json.loads(raw), r.headers

titles = lambda j: [e["title"] for e in j["entries"]]

# ── not logged in: 401 and nothing asked of AniList
assert call("/al/list?status=CURRENT")[0] == 401 and calls == []
ms._auth_write({"token": GOOD, "expiresAt": int(time.time()) + 86400,
                "viewer": {"id": 42, "name": "V", "scoreFormat": "POINT_10"}})

# ── Reading: the whole list is read in chunks, custom lists left out, the default sort is the score
st, j, h = call("/al/list?status=CURRENT")
assert st == 200 and calls == [1, 2, 3], calls
assert h.get("Access-Control-Allow-Origin") is None, "the list must not allow other web pages"
assert j["status"] == "CURRENT" and j["scoreFormat"] == "POINT_10" and j["total"] == 5, j["total"]
assert j["counts"] == {"CURRENT": 5, "PLANNING": 1, "COMPLETED": 2, "PAUSED": 1, "DROPPED": 1, "REPEATING": 0}, j["counts"]
assert titles(j) == ["Blue Lock", "Sasayaku", "Watashi no", "Bocchi the Rock!", "Ao no Hako"], titles(j)   # unscored last
e = j["entries"][0]
assert e["id"] == "al:1" and e["anilistId"] == 1 and e["score"] == 10 and e["score100"] == 100
assert e["progress"] == 322 and e["chapters"] == 0 and e["type"] == "MANGA" and e["status"] == "Releasing"
assert e["image"].endswith(ms.proxy_url("https://img/1.jpg")[-20:]) and e["listStatus"] == "CURRENT"
ao = j["entries"][-1]
assert ao["chapters"] == 250 and ao["volumes"] == 28 and ao["progress"] == 164

# ── a tab is cut out of the copy already read: AniList is not asked again
n = len(calls)
st, j, _ = call("/al/list?status=COMPLETED")
assert titles(j) == ["Solo Leveling", "One Shot Thing"] and j["counts"]["CURRENT"] == 5 and len(calls) == n
assert j["entries"][0]["type"] == "MANHWA" and j["entries"][1]["type"] == "ONE-SHOT"
assert titles(call("/al/list?status=DROPPED")[1]) == ["Chainsaw Man"]
assert titles(call("/al/list?status=PLANNING")[1]) == ["Ring Ring"]
assert call("/al/list?status=PLANNING")[1]["entries"][0]["type"] == "NOVEL"
assert titles(call("/al/list?status=PAUSED")[1]) == ["On Hold"]
assert titles(call("/al/list?status=REPEATING")[1]) == []
assert titles(call("/al/list")[1])[0] == "Blue Lock", "no status means Reading"

# ── filters (all of them together, like AniList's)
f = lambda qs: titles(call("/al/list?status=CURRENT&" + qs)[1])
assert f("genres=Romance") == ["Sasayaku", "Watashi no", "Ao no Hako"]
assert f("genres=Romance,Sports") == ["Ao no Hako"], "every genre asked for has to be there"
assert f("tags=Marriage") == ["Watashi no"] and f("tags=Marriage|Football") == []
assert f("year=2021") == ["Watashi no", "Ao no Hako"]
assert f("mstatus=RELEASING") == ["Blue Lock"] and f("mstatus=RELEASING,FINISHED") != []
assert f("country=KR") == [] and titles(call("/al/list?status=COMPLETED&country=KR")[1]) == ["Solo Leveling"]
assert titles(call("/al/list?status=COMPLETED&format=ONE_SHOT")[1]) == ["One Shot Thing"]
assert titles(call("/al/list?status=PLANNING&format=NOVEL")[1]) == ["Ring Ring"]
assert f("q=blue") == ["Blue Lock"] and f("q=%20ROCK") == ["Bocchi the Rock!"] and f("q=romaji")  != []
assert f("q=zzz") == []
j = call("/al/list?status=CURRENT&genres=Sports")[1]
assert j["total"] == 2 and j["counts"]["CURRENT"] == 5, "the tab counts ignore the filters; total is what is shown"
assert f("genres=Nope") == f(""), "an unknown genre is ignored, as in Browse"

# ── sorts
assert f("sort=TITLE") == ["Ao no Hako", "Blue Lock", "Bocchi the Rock!", "Sasayaku", "Watashi no"]
assert f("sort=PROGRESS") == ["Blue Lock", "Ao no Hako", "Sasayaku", "Watashi no", "Bocchi the Rock!"]
assert f("sort=UPDATED") == ["Watashi no", "Blue Lock", "Sasayaku", "Bocchi the Rock!", "Ao no Hako"]
assert f("sort=ADDED") == ["Bocchi the Rock!", "Ao no Hako", "Watashi no", "Sasayaku", "Blue Lock"]
assert f("sort=nonsense") == f("sort=SCORE")

# ── bad input
assert call("/al/list?status=WATCHING")[0] == 400
assert call("/al/list?status=CURRENT&format=COMIC")[0] == 400

# ── a save of the track sheet drops the copy, the next read asks AniList again
n = len(calls)
ms._track_save(1, {"progress": 1})
call("/al/list?status=CURRENT")
assert len(calls) > n, "the list changed on AniList, so it is read again"

# ── other origins and hosts are refused, as for the login and the tracking
assert call("/al/list?status=CURRENT", headers={"Origin": "https://evil.example"})[0] == 403
assert call("/al/list?status=CURRENT", headers={"Host": "evil.example"})[0] == 403

# ── a login AniList turned down: 401, and the dead login is forgotten
ms._cache_drop("al:list:")
revoked["on"] = True
st, j, _ = call("/al/list?status=CURRENT")
assert st == 401 and "log in" in j["error"].lower(), j
print("ok")
