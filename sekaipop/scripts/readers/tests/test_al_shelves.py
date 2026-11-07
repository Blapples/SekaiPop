"""The profile page's list-derived extras: the score spread, Almost done, Stalled and the Planning
shelf (all cut out of the one copy of the AniList list, no new question), with AniList mocked.
Run: python3 tests/test_al_shelves.py"""
import os, sys, json, time, base64, tempfile, importlib.util
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
DAY = 86400
_id = [0]
def entry(mid, status, title, score=0, score100=None, progress=0, chapters=0, updated=0, avg=80):
    _id[0] += 1
    s100 = score * 10 if score100 is None else score100
    return {"id": _id[0], "status": status, "score": score, "score100": s100,
            "progress": progress, "progressVolumes": 0, "updatedAt": updated, "createdAt": 1,
            "media": {"id": mid, "title": {"english": title, "romaji": title, "native": None},
                      "coverImage": {"large": f"https://img/{mid}.jpg"}, "format": "MANGA",
                      "status": "RELEASING", "chapters": chapters, "volumes": 0, "genres": [],
                      "countryOfOrigin": "JP", "startDate": {"year": 2020}, "averageScore": avg, "tags": []}}

ENTRIES = [
    entry(1,  "CURRENT",  "Three Left",   score=8,  progress=20, chapters=23, updated=NOW - 2 * DAY),
    entry(2,  "CURRENT",  "One Left",     score=8,  progress=9,  chapters=10, updated=NOW - 10 * DAY),
    entry(3,  "CURRENT",  "Gone Quiet",   score=0,  progress=5,  chapters=50, updated=NOW - 45 * DAY),
    entry(4,  "CURRENT",  "Long Gone",    score=10, progress=7,  chapters=0,  updated=NOW - 100 * DAY),
    entry(5,  "CURRENT",  "Not Started",  progress=0,  chapters=12, updated=NOW),
    entry(6,  "CURRENT",  "Caught Up",    progress=12, chapters=12, updated=NOW - 3 * DAY),
    entry(7,  "CURRENT",  "No Time",      progress=1,  chapters=10, updated=0),
    entry(8,  "CURRENT",  "Six Left",     progress=4,  chapters=10, updated=NOW - DAY),
    entry(9,  "PLANNING", "Plan Low",     avg=70),
    entry(10, "PLANNING", "Plan High",    avg=90),
    entry(11, "PLANNING", "Plan Unrated", avg=0),
    entry(12, "COMPLETED", "Done A",      score=8),
    entry(13, "COMPLETED", "Done B",      score=5),
]
calls = {"list": 0}

def fake_request(query, variables, token=None):
    assert token == GOOD
    if "MediaListCollection" in query:
        calls["list"] += 1
        lists = {}
        for e in ENTRIES:
            lists.setdefault(e["status"], []).append(e)
        return {"MediaListCollection": {"hasNextChunk": False, "lists": [
            {"status": s, "isCustomList": False, "entries": es} for s, es in lists.items()]}}
    raise AssertionError(query)
ms._al_request = fake_request

def overview(fmt):
    ms._auth_write({"token": GOOD, "expiresAt": NOW + DAY,
                    "viewer": {"id": 42, "name": "V", "scoreFormat": fmt}})
    ms._cache_drop("al:list:42")
    return ms.al_overview()

# ── Almost done: a known total, started, 1..5 chapters left; the fewest left first
j = overview("POINT_10")
assert [r["title"] for r in j["almostDone"]] == ["One Left", "Three Left"], [r["title"] for r in j["almostDone"]]
assert [r["left"] for r in j["almostDone"]] == [1, 3] and j["almostTotal"] == 2
assert all(r["chapters"] > 0 and r["progress"] > 0 for r in j["almostDone"])

# ── Stalled: Reading and idle 30+ days (the longest idle first); no time on the entry is not stalled
assert [r["title"] for r in j["stalled"]] == ["Long Gone", "Gone Quiet"], [r["title"] for r in j["stalled"]]
assert [r["idleDays"] for r in j["stalled"]] == [100, 45] and j["stalledTotal"] == 2
assert "No Time" not in [r["title"] for r in j["stalled"]]
assert all(r["id"].startswith("al:") for r in j["stalled"]), "tappable ids are the Library's"

# ── Planning shelf: AniList's average first, unrated last; only Planning titles
assert [r["title"] for r in j["planning"]] == ["Plan High", "Plan Low", "Plan Unrated"], [r["title"] for r in j["planning"]]
assert j["planningTotal"] == 3

# ── shelves are capped but the totals are not
many = [entry(100 + i, "PLANNING", f"P{i:02d}", avg=50 + (i % 40)) for i in range(40)]
ENTRIES.extend(many)
j2 = overview("POINT_10")
assert len(j2["planning"]) == ms.AL_SHELF_SHOWN and j2["planningTotal"] == 43
del ENTRIES[-40:]

# ── score spread: one slot per point of the user's scale, unscored titles not counted
j = overview("POINT_10")
assert j["scoreDist"]["max"] == 10 and len(j["scoreDist"]["counts"]) == 10
c = j["scoreDist"]["counts"]
assert c[7] == 3 and c[9] == 1 and c[4] == 1 and sum(c) == 5, c      # 8,8,8 | 10 | 5

# a 100-point score goes to the nearest ten: 85 -> 9, 84 -> 8
ENTRIES.append(entry(50, "COMPLETED", "Eighty Five", score=85, score100=85))
ENTRIES.append(entry(51, "COMPLETED", "Eighty Four", score=84, score100=84))
j = overview("POINT_100")
assert j["scoreDist"]["max"] == 10
c = j["scoreDist"]["counts"]
assert c[8] == 1 and c[7] == 4, c      # the 85 is a 9; the 84 joins the three 8s
ENTRIES[-2:] = []

j = overview("POINT_5")
assert j["scoreDist"]["max"] == 5 and len(j["scoreDist"]["counts"]) == 5
j = overview("POINT_3")
assert j["scoreDist"]["max"] == 3 and len(j["scoreDist"]["counts"]) == 3 and sum(j["scoreDist"]["counts"]) == 5
j = overview("")                 # a format we were not told: tens of the 0-100 score
assert j["scoreDist"]["max"] == 10

# ── an empty list answers with empty shelves and an all-zero spread
saved = list(ENTRIES); ENTRIES.clear()
j = overview("POINT_10")
assert j["almostDone"] == [] and j["stalled"] == [] and j["planning"] == []
assert sum(j["scoreDist"]["counts"]) == 0 and j["almostTotal"] == 0
ENTRIES.extend(saved)

# ── all of it is cut out of the one copy of the list
calls["list"] = 0
ms._cache_drop("al:list:42")
ms.al_overview(); ms.al_overview(); ms.al_pick()
assert calls["list"] == 1, calls
print("ok")
