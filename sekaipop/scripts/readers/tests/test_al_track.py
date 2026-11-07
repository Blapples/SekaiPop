"""AniList tracking: what the panel reports as read goes on the user's list (only ever up), a
title is started / completed on the way, the track sheet can set anything, and every route
needs the login and refuses other origins, with AniList mocked.
Run: python3 tests/test_al_track.py"""
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

# ── a tiny AniList: media with a chapter count and the user's entry for each
MEDIA = {
    100: {"id": 100, "chapters": 10, "volumes": 2, "siteUrl": "https://anilist.co/manga/100", "entry": None},
    200: {"id": 200, "chapters": 0,  "volumes": 0, "siteUrl": "https://anilist.co/manga/200",
          "entry": {"id": 9, "status": "PAUSED", "score": 8, "score100": 80, "progress": 4, "progressVolumes": 0}},
}
saves = []
revoked = {"on": False}

def fake_request(query, variables, token=None):
    if revoked["on"]:
        raise ms.AniListAuthError("Your AniList login has run out. Log in again.")
    assert token == GOOD, "tracking must be asked as the logged-in user"
    m = MEDIA[variables.get("id", variables.get("mediaId"))]
    if query.lstrip().startswith("mutation"):
        saves.append({k: v for k, v in variables.items() if k != "mediaId"})
        e = dict(m["entry"] or {"id": 1, "status": "PLANNING", "progress": 0, "progressVolumes": 0})
        for k in ("status", "progress", "progressVolumes"):
            if k in variables:
                e[k] = variables[k]
        m["entry"] = e
        return {"SaveMediaListEntry": e}
    return {"Media": {"id": m["id"], "chapters": m["chapters"], "volumes": m["volumes"],
                      "siteUrl": m["siteUrl"], "mediaListEntry": m["entry"]}}
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

# ── not logged in: nothing is asked of AniList
assert call("/al/track?id=100")[0] == 401
assert call("/al/track/progress", {"anilistId": 100, "progress": 3})[0] == 401
assert call("/al/track/set", {"anilistId": 100, "status": "CURRENT"})[0] == 401
assert saves == []

ms._auth_write({"token": GOOD, "expiresAt": int(time.time()) + 86400, "viewer": {"id": 42, "name": "V"}})

# ── reading a title that is not on the list yet: it is started
st, j, h = call("/al/track?id=100")
assert st == 200 and j["entry"] is None and j["chapters"] == 10
assert h.get("Access-Control-Allow-Origin") is None, "tracking must not allow other web pages"
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 3})
assert st == 200 and j["changed"] is True, j
assert j["entry"]["status"] == "CURRENT" and j["entry"]["progress"] == 3, j
assert saves[-1] == {"progress": 3, "status": "CURRENT"}, saves[-1]

# ── reading further goes up; reading something older, or the same, changes nothing
n = len(saves)
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 7})
assert j["entry"]["progress"] == 7 and saves[-1] == {"progress": 7}, saves[-1]
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 2})
assert j["changed"] is False and j["entry"]["progress"] == 7 and len(saves) == n + 1
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 7})
assert j["changed"] is False and len(saves) == n + 1

# ── the last chapter AniList knows completes it (and is not asked to again)
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 10})
assert j["entry"]["status"] == "COMPLETED" and j["entry"]["progress"] == 10, j
n = len(saves)
call("/al/track/progress", {"anilistId": 100, "progress": 10})
assert len(saves) == n

# ── a paused title is picked up again; no chapter count means never completed
st, j, _ = call("/al/track/progress", {"anilistId": 200, "progress": 9})
assert j["entry"]["status"] == "CURRENT" and j["entry"]["progress"] == 9, j

# ── the user's own score comes with the entry, and an automatic update does not drop it
assert j["entry"]["score"] == 8 and j["entry"]["score100"] == 80, j
st, j, _ = call("/al/track?id=200")
assert j["entry"]["score"] == 8 and j["entry"]["score100"] == 80, j
st, j, _ = call("/al/track?id=100")
assert j["entry"] is None or (j["entry"]["score"] == 0 and j["entry"]["score100"] == 0), j      # unscored: 0, not missing

# ── volumes (a series listed by volume)
st, j, _ = call("/al/track/progress", {"anilistId": 200, "progress": 0, "volumes": 2})
assert j["entry"]["progressVolumes"] == 2 and saves[-1] == {"progressVolumes": 2}, saves[-1]

# ── nothing read yet does not start anything
MEDIA[100]["entry"] = None
n = len(saves)
st, j, _ = call("/al/track/progress", {"anilistId": 100, "progress": 0})
assert j["changed"] is False and len(saves) == n and j["entry"] is None

# ── by hand: anything goes, including lowering
st, j, _ = call("/al/track/set", {"anilistId": 200, "status": "DROPPED", "progress": 2})
assert st == 200 and j["entry"]["status"] == "DROPPED" and j["entry"]["progress"] == 2, j
st, j, _ = call("/al/track/set", {"anilistId": 200, "progress": 0})
assert j["entry"]["progress"] == 0 and saves[-1] == {"progress": 0}, saves[-1]
assert call("/al/track/set", {"anilistId": 200, "status": "WATCHING"})[0] == 400
assert call("/al/track/set", {"anilistId": 200})[0] == 400
assert call("/al/track/set", {"anilistId": 200, "progress": -1})[0] == 400
assert call("/al/track/set", {"anilistId": 200, "progress": "many"})[0] == 400
assert call("/al/track/set", {"anilistId": "x", "progress": 1})[0] == 400
assert call("/al/track/progress", {"anilistId": 100, "progress": 10 ** 9})[0] == 400
assert call("/al/track?id=abc")[0] == 400

# ── other origins and hosts are refused, as for the login
assert call("/al/track?id=100", headers={"Origin": "https://evil.example"})[0] == 403
assert call("/al/track/progress", {"anilistId": 100, "progress": 5}, {"Origin": "https://evil.example"})[0] == 403
assert call("/al/track/set", {"anilistId": 100, "progress": 5}, {"Host": "evil.example"})[0] == 403

# ── a login AniList turned down: 401, and the dead login is forgotten
revoked["on"] = True
st, j, _ = call("/al/track?id=100")
assert st == 401 and "log in" in j["error"].lower(), j
print("ok")
