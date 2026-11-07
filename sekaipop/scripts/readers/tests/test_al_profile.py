"""The profile page's data: the bio (as plain text), follower / following totals, the genre
statistics, Reading now and Top rated (cut out of the list already read), the random Planning
pick, and the reading-activity days, with AniList mocked.
Run: python3 tests/test_al_profile.py"""
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
def entry(mid, status, title, score100=0, progress=0, chapters=0, updated=0):
    _id[0] += 1
    return {"id": _id[0], "status": status, "score": score100 / 10, "score100": score100,
            "progress": progress, "progressVolumes": 0, "updatedAt": updated, "createdAt": 1,
            "media": {"id": mid, "title": {"english": title, "romaji": title, "native": None},
                      "coverImage": {"large": f"https://img/{mid}.jpg"}, "format": "MANGA",
                      "status": "RELEASING", "chapters": chapters, "volumes": 0, "genres": [],
                      "countryOfOrigin": "JP", "startDate": {"year": 2020}, "averageScore": 80, "tags": []}}

ENTRIES = [
    entry(1, "CURRENT",   "Old Read",    90, 10, 0, updated=100),
    entry(2, "CURRENT",   "Newest Read", 80, 30, 120, updated=300),
    entry(3, "CURRENT",   "Middle Read",  0, 5,  0, updated=200),
    entry(4, "COMPLETED", "Ten A",      100, 50, 50, updated=150),
    entry(5, "COMPLETED", "Ten B",      100, 20, 20, updated=250),
    entry(6, "DROPPED",   "Nine",        90, 3,  0, updated=10),
    entry(7, "PLANNING",  "Plan One",     0, 0,  0),
    entry(8, "PLANNING",  "Plan Two",     0, 0,  0),
    entry(9, "PLANNING",  "Plan Three",   0, 0,  0),
]

BIO = ("Hello **there**!<br>img220(https://x/y.png) ~!a spoiler!~ [my site](https://a.b) "
       "https://c.d\n\n\n## Likes\nromance")
today = time.time()
def ts(days_ago, hour=12):
    t = time.localtime(today - days_ago * 86400)
    return int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, hour, 0, 0, 0, 0, -1)))
ACTIVITY = [ts(0, 9), ts(0, 20), ts(1), ts(5), ts(5, 8), ts(5, 23), ts(400)]   # the last is too old
act_pages = {"per": 3}
calls = {"list": 0, "profile": [], "activity": []}

def fake_request(query, variables, token=None):
    assert token == GOOD
    if query.lstrip().startswith("mutation"):
        return {"SaveMediaListEntry": {"id": 1, "status": "CURRENT", "progress": 1, "progressVolumes": 0}}
    if "MediaListCollection" in query:
        calls["list"] += 1
        lists = {}
        for e in ENTRIES:
            lists.setdefault(e["status"], []).append(e)
        return {"MediaListCollection": {"hasNextChunk": False, "lists": [
            {"status": s, "isCustomList": False, "entries": es} for s, es in lists.items()]}}
    if "Viewer" in query:
        calls["profile"].append(dict(variables))
        return {"Viewer": {"id": 42, "name": "V", "siteUrl": "https://anilist.co/user/V", "bannerImage": None,
                           "about": BIO, "avatar": {"large": "https://img/a.png"},
                           "statistics": {"manga": {"count": 9, "chaptersRead": 1234, "volumesRead": 3, "meanScore": 81.5,
                                                    "genres": [{"genre": "Romance", "count": 20, "meanScore": 82},
                                                               {"genre": "Action", "count": 10, "meanScore": 70.5},
                                                               {"genre": "", "count": 1, "meanScore": 0}]}},
                           "favourites": {"manga": {"pageInfo": {"total": 0}, "nodes": []}}},
                "followers": {"pageInfo": {"total": 12}, "followers": [{"id": 1}]},
                "following": {"pageInfo": {"total": 34}, "following": [{"id": 2}]}}
    if "activities(" in query:
        calls["activity"].append(dict(variables))
        per, page = act_pages["per"], variables["page"]
        part = ACTIVITY[(page - 1) * per: page * per]
        rows = [{"createdAt": a} for a in part] + ([{}] if page == 1 else [])    # an activity of another kind: {}
        return {"Page": {"pageInfo": {"hasNextPage": page * per < len(ACTIVITY)}, "activities": rows}}
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

# ── logged out: 401 on every route, AniList not asked
for path in ("/al/overview", "/al/pick", "/al/activity", "/al/profile"):
    assert call(path)[0] == 401, path
assert calls["list"] == 0 and not calls["profile"] and not calls["activity"]
ms._auth_write({"token": GOOD, "expiresAt": int(time.time()) + 86400,
                "viewer": {"id": 42, "name": "V", "scoreFormat": "POINT_10"}})

# ── the plain-text bio
t = ms._al_plain_text(BIO)
assert t == "Hello there!\nmy site\n\nLikes\nromance", repr(t)
assert "spoiler" not in t and "http" not in t and "img220" not in t
assert ms._al_plain_text(None) == ""
cut = ms._al_plain_text("x" * 2000)
assert cut == "x" * ms.AL_ABOUT_MAX + "\u2026", "no space to cut at: cut at the limit"
long = ms._al_plain_text(("word " * 400).strip(), 50)
assert long.endswith("\u2026") and len(long) <= 51, long

# ── profile: bio, social, genres; the user id goes with the question
# AniList's followers(userId:) / following(userId:) take Int!, so the variable has to be declared Int! (Int is refused)
assert "$uid:Int!" in ms._AL_PROFILE_Q.replace(" ", ""), "the user id variable must be Int!"
st, j, h = call("/al/profile?fresh=1")
assert st == 200 and h.get("Access-Control-Allow-Origin") is None
assert calls["profile"] == [{"perPage": ms.AL_FAV_ASKED, "uid": 42}], calls["profile"]
assert j["about"] == t and j["followers"] == 12 and j["following"] == 34
assert j["genres"] == [{"genre": "Romance", "count": 20, "meanScore": 82.0},
                       {"genre": "Action", "count": 10, "meanScore": 70.5}], j["genres"]
assert j["stats"]["chaptersRead"] == 1234

# ── overview: Reading now (latest touched first), Top rated (score, then newest), counts
st, j, h = call("/al/overview")
assert st == 200 and h.get("Access-Control-Allow-Origin") is None
assert calls["list"] == 1
assert [r["title"] for r in j["reading"]] == ["Newest Read", "Middle Read", "Old Read"], j["reading"]
assert j["readingTotal"] == 3 and j["scoreFormat"] == "POINT_10"
assert [r["title"] for r in j["top"]] == ["Ten B", "Ten A", "Old Read", "Nine", "Newest Read"], [r["title"] for r in j["top"]]
assert j["counts"]["CURRENT"] == 3 and j["counts"]["PLANNING"] == 3 and j["counts"]["COMPLETED"] == 2
r0 = j["reading"][0]
assert r0["id"] == "al:2" and r0["progress"] == 30 and r0["chapters"] == 120 and r0["updatedAt"] == 300
assert all(r["score100"] > 0 for r in j["top"]), "unscored titles are not top rated"
call("/al/overview"); call("/al/pick")
assert calls["list"] == 1, "all of it comes from the one copy of the list"

# ── pick: only from Planning, never the excluded one, the only one when there is just one
seen = set()
for _ in range(60):
    st, j, _h = call("/al/pick?exclude=8")
    assert st == 200 and j["total"] == 3 and j["entry"]["listStatus"] == "PLANNING"
    assert j["entry"]["anilistId"] != 8
    seen.add(j["entry"]["anilistId"])
assert seen == {7, 9}, seen
st, j, _h = call("/al/pick")
assert j["entry"]["title"] in ("Plan One", "Plan Two", "Plan Three") and j["scoreFormat"] == "POINT_10"
assert call("/al/pick?exclude=abc")[0] == 200, "a bad exclude is ignored"
planning = [e for e in ENTRIES if e["status"] == "PLANNING"]
for e in planning[1:]:
    ENTRIES.remove(e)
ms._cache_drop("al:list:")
j = call("/al/pick?exclude=7")[1]
assert j["total"] == 1 and j["entry"]["anilistId"] == 7, "the only one is shown even if it is the excluded"
ENTRIES[:] = [e for e in ENTRIES if e["status"] != "PLANNING"]
ms._cache_drop("al:list:")
j = call("/al/pick")[1]
assert j == {"total": 0, "scoreFormat": "POINT_10", "entry": None}, j

# ── activity: days counted in local time, the old and the odd ones skipped, paged
st, j, h = call("/al/activity")
assert st == 200 and h.get("Access-Control-Allow-Origin") is None
d = lambda n: time.strftime("%Y-%m-%d", time.localtime(today - n * 86400))
assert j["counts"] == {d(0): 2, d(1): 1, d(5): 3}, j["counts"]
assert j["total"] == 6 and j["days"] == 182 and j["capped"] is False
assert [c["page"] for c in calls["activity"]] == [1, 2, 3], "a page at a time until there is no next"
assert calls["activity"][0]["uid"] == 42 and calls["activity"][0]["since"] <= int(time.time()) - 181 * 86400
n = len(calls["activity"])
call("/al/activity")
assert len(calls["activity"]) == n, "kept ten minutes"
call("/al/activity?fresh=1")
assert len(calls["activity"]) > n, "fresh asks again"

# ── a very busy account stops at the page limit and says so
ACTIVITY[:] = [ts(1)] * 400
act_pages["per"] = 50
ms._cache_drop("al:activity:")
j = call("/al/activity")[1]
assert j["capped"] is True and j["total"] == 50 * ms.AL_ACTIVITY_PAGES, j["total"]

# ── a save of the track sheet drops the activity too
n = len(calls["activity"])
ms._track_save(1, {"progress": 1})
call("/al/activity")
assert len(calls["activity"]) > n

# ── other origins and hosts are refused
for path in ("/al/overview", "/al/pick", "/al/activity"):
    assert call(path, {"Origin": "https://evil.example"})[0] == 403, path
    assert call(path, {"Host": "evil.example"})[0] == 403, path
print("ok")
