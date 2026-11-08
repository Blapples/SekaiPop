"""The novel reader's AniList tracking (novel_server/anilist.py and its /al/* routes): novels only,
the manga reader's login, matching, progress that only goes up, the guard on the endpoints.
No network: AniList is a fake. Run: python3 tests/test_novel_al.py"""
import os, sys, json, tempfile, threading, urllib.request, urllib.error, time

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="novel-al-test-")
os.environ["HOME"] = TMP                                   # the data folders are made at import
sys.path.insert(0, os.path.join(HERE, "..", "novel_server"))

import anilist as al
import server

# ── a fake AniList ──────────────────────────────────────────────────────────
NOVELS = [
    {"id": 101, "format": "NOVEL", "chapters": 40, "volumes": 5, "status": "FINISHED", "siteUrl": "u101",
     "synonyms": ["Re:Zero Light Novel"], "title": {"romaji": "Re:Zero kara Hajimeru Isekai Seikatsu",
     "english": "Re:ZERO -Starting Life in Another World-", "native": None},
     "coverImage": {"large": "c101"}, "startDate": {"year": 2014}},
    {"id": 102, "format": "NOVEL", "chapters": None, "volumes": None, "status": "RELEASING", "siteUrl": "u102",
     "synonyms": [], "title": {"romaji": "Omniscient Reader", "english": "Omniscient Reader's Viewpoint", "native": None},
     "coverImage": {"large": "c102"}, "startDate": {"year": 2018}},
]
MANGA = {"id": 900, "format": "MANGA", "chapters": 10, "volumes": 1, "status": "FINISHED", "siteUrl": "u900",
         "synonyms": [], "title": {"romaji": "A Manga", "english": "A Manga", "native": None},
         "coverImage": {"large": "c900"}, "startDate": {"year": 2010}}
ENTRIES = {}                     # media id -> list entry
CALLS = []


def fake(query, variables, token=None):
    CALLS.append((query.strip().split("{")[0].strip()[:20], dict(variables), token))
    if "Page(" in query:
        assert "format:NOVEL" in query.replace(" ", "") or "format: NOVEL" in query, "search must ask for novels only"
        q = variables["q"].lower()
        return {"Page": {"media": [m for m in NOVELS if q in json.dumps(m["title"]).lower() or q in " ".join(m["synonyms"]).lower()]}}
    if "SaveMediaListEntry" in query:
        assert token == "tok-good"
        e = ENTRIES.setdefault(variables["mediaId"], {"id": 1, "status": "CURRENT", "score": 0, "score100": 0,
                                                       "progress": 0, "progressVolumes": 0})
        for k in ("status", "progress", "progressVolumes"):
            if k in variables:
                e[k] = variables[k]
        return {"SaveMediaListEntry": dict(e)}
    mid = variables["id"]
    media = next((m for m in NOVELS + [MANGA] if m["id"] == mid), None)
    if media is None:
        return {"Media": None}
    media = dict(media)
    if "mediaListEntry" in query:
        assert token == "tok-good", "tracking needs the login"
        media["mediaListEntry"] = dict(ENTRIES[mid]) if mid in ENTRIES else None
    return {"Media": media}


al._request = fake

# ── the login is the manga reader's file ────────────────────────────────────
assert al.status() == {"loggedIn": False, "expired": False, "viewer": None}
try:
    al.track_info(101); raise SystemExit("tracking without a login must be refused")
except al.AlError as e:
    assert e.status == 401
os.makedirs(al.MANGA_DIR, exist_ok=True)
json.dump({"token": "tok-good", "expiresAt": int(time.time()) + 3600,
           "viewer": {"id": 7, "name": "me", "avatar": "a", "siteUrl": "s", "scoreFormat": "POINT_10"}},
          open(al.AUTH_FILE, "w"))
st = al.status()
assert st["loggedIn"] is True and st["viewer"]["name"] == "me" and "token" not in json.dumps(st)
json.dump({"token": "old", "expiresAt": int(time.time()) - 5}, open(al.AUTH_FILE, "w"))
assert al.status()["expired"] is True and al.status()["loggedIn"] is False
json.dump({"token": "tok-good", "expiresAt": int(time.time()) + 3600,
           "viewer": {"id": 7, "name": "me"}}, open(al.AUTH_FILE, "w"))

# ── names ───────────────────────────────────────────────────────────────────
assert al.similarity("Re:Zero", "re zero") == 1.0
assert al.similarity("", "x") == 0.0
assert al.similarity("Totally Different", "Omniscient Reader") < 0.5

# ── search: novels only ─────────────────────────────────────────────────────
r = al.search("omniscient")
assert [c["anilistId"] for c in r] == [102] and r[0]["title"] == "Omniscient Reader's Viewpoint"
assert al.search("  ") == []

# ── matching ────────────────────────────────────────────────────────────────
m = al.match_get("lnreader:a", "Omniscient Reader's Viewpoint")["match"]
assert m == {"anilistId": 102, "title": "Omniscient Reader's Viewpoint", "manual": False}
n = len(CALLS)
assert al.match_get("lnreader:a", "anything")["match"]["anilistId"] == 102     # kept: no new request
assert len(CALLS) == n
assert al.match_get("lnreader:b", "Omniscient")["match"] is None               # too far from the name
n = len(CALLS)
assert al.match_get("lnreader:b", "Omniscient")["match"] is None
assert len(CALLS) == n                                                         # and not asked again
# a manga cannot be picked
try:
    al.match_set("lnreader:b", 900); raise SystemExit("a manga must be refused")
except al.AlError as e:
    assert e.status == 400 and "not a novel" in str(e)
m = al.match_set("lnreader:b", 102)["match"]
assert m["manual"] is True and m["anilistId"] == 102
assert al.match_get("lnreader:b", "x")["match"]["manual"] is True
al.match_clear("lnreader:b")
assert al.match_get("lnreader:b", "")["match"] is None

# ── tracking ────────────────────────────────────────────────────────────────
try:
    al.track_info(900); raise SystemExit("a manga must not be tracked")
except al.AlError as e:
    assert e.status == 400
try:
    al.track_progress(900, 3); raise SystemExit("a manga must not be tracked")
except al.AlError:
    pass
assert 900 not in ENTRIES

v = al.track_info(101)
assert v["entry"] is None and v["chapters"] == 40
v = al.track_progress(101, 5)                              # not on the list: becomes Reading at 5
assert v["changed"] is True and v["entry"]["status"] == "CURRENT" and v["entry"]["progress"] == 5
v = al.track_progress(101, 3)                              # reading an older chapter never lowers it
assert v["changed"] is False and v["entry"]["progress"] == 5
v = al.track_progress(101, 8, 2)
assert v["entry"]["progress"] == 8 and v["entry"]["progressVolumes"] == 2
v = al.track_progress(101, 40)                             # the last chapter AniList knows: Completed
assert v["entry"]["status"] == "COMPLETED"
v = al.track_progress(102, 12)                             # no chapter count known: stays Reading
assert v["entry"]["status"] == "CURRENT" and v["entry"]["progress"] == 12
ENTRIES[102]["status"] = "PLANNING"
v = al.track_progress(102, 13)
assert v["entry"]["status"] == "CURRENT"
v = al.track_set(101, "DROPPED", 2)                        # by hand it may lower
assert v["entry"]["status"] == "DROPPED" and v["entry"]["progress"] == 2
for bad in ({"status": "NOPE"}, {}, {"progress": -1}, {"progress": "x"}):
    try:
        al.track_set(101, **bad); raise SystemExit("bad input must be refused: %r" % bad)
    except al.AlError as e:
        assert e.status == 400
for bad in (None, "", "abc", 0, -3):
    try:
        al.track_info(bad); raise SystemExit("bad id")
    except al.AlError:
        pass

# ── the HTTP routes ─────────────────────────────────────────────────────────
srv = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
server.PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % server.PORT


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


s, j = call("GET", "/al/status")
assert s == 200 and j["loggedIn"] is True
s, j = call("GET", "/al/search?q=omniscient")
assert s == 200 and j[0]["anilistId"] == 102
s, j = call("POST", "/al/track/progress", {"anilistId": 101, "progress": 30})
assert s == 200 and j["entry"]["progress"] == 30, j
s, j = call("POST", "/al/track/progress", {"anilistId": 900, "progress": 3})
assert s == 400 and "not a novel" in j["error"], (s, j)
s, j = call("POST", "/al/match/set", {"novelId": "lnreader:z", "anilistId": 102})
assert s == 200 and j["match"]["anilistId"] == 102
s, j = call("GET", "/al/match?novelId=lnreader:z&title=whatever")
assert j["match"]["manual"] is True
s, j = call("POST", "/al/match/clear", {"novelId": "lnreader:z"})
assert j["match"] is None
s, j = call("GET", "/al/nothing")
assert s == 404
# a web page (an Origin that is not this server) cannot reach any of it
for method, path, body in (("GET", "/al/status", None), ("POST", "/al/track/set", {"anilistId": 101, "status": "DROPPED"})):
    s, j = call(method, path, body, {"Origin": "http://evil.example"})
    assert s == 403 and j["error"] == "not allowed", (path, s, j)
s, j = call("GET", "/al/status", headers={"Origin": "http://127.0.0.1:%d" % server.PORT})
assert s == 200
assert ENTRIES[101]["status"] != "DROPPED" or ENTRIES[101]["progress"] == 30   # the refused set changed nothing
assert ENTRIES[101]["progress"] == 30
srv.shutdown()
print("novel AniList: ok")
