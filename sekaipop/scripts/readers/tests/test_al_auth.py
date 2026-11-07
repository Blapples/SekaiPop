"""AniList login: the client ID, the start / callback / token handshake, the saved file, logout,
and the refusals (wrong nonce, other origin or host, a token AniList rejects), with AniList mocked.
Run: python3 tests/test_al_auth.py"""
import os, sys, json, stat, time, base64, tempfile, importlib.util, threading, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR = tmp
ms.AL_AUTH_FILE = os.path.join(tmp, "anilist_auth.json")
os.environ.pop("SEKAIPOP_ANILIST_CLIENT_ID", None)

def jwt(exp):
    b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
    return b({"alg": "none"}) + "." + b({"exp": exp}) + "." + "sig" * 8

GOOD = jwt(int(time.time()) + 86400 * 300)
calls = []
def fake_request(query, variables, token=None):
    calls.append((query, token))
    if token != GOOD:
        raise ms.AniListAuthError("nope")
    return {"Viewer": {"id": 42, "name": "Vince", "siteUrl": "https://anilist.co/user/Vince",
                       "avatar": {"large": "https://img/l.png", "medium": "https://img/m.png"},
                       "mediaListOptions": {"scoreFormat": "POINT_10"}}}
real_request = ms._al_request
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
    ctype = r.headers.get("Content-Type", "")
    return r.status if hasattr(r, "status") else r.code, (json.loads(raw) if "json" in ctype else raw.decode()), r.headers

# ── nothing yet
st, j, h = call("/al/auth/status")
assert st == 200 and j["loggedIn"] is False and j["hasClientId"] is False and j["viewer"] is None, j
assert h.get("Access-Control-Allow-Origin") is None, "login endpoints must not allow other web pages"
assert j["redirectUri"] == ms.AL_REDIRECT

# ── start needs a client ID; the ID must be the number AniList shows
assert call("/al/auth/start", {})[0] == 400
assert call("/al/auth/client", {"clientId": "abc"})[0] == 400
assert call("/al/auth/client", {"clientId": "1; DROP"})[0] == 400
st, j, _ = call("/al/auth/client", {"clientId": " 12345 "})
assert st == 200 and j["hasClientId"] is True and j["loggedIn"] is False

# ── the page AniList sends the browser back to: no nonce before a login is started
st, page, h = call("/al/auth/callback")
assert st == 200 and "var nonce = \"\";" in page, page
assert "no-store" in h["Cache-Control"] and "default-src 'none'" in h["Content-Security-Policy"]

st, start, _ = call("/al/auth/start", {})
assert st == 200 and start["nonce"] and start["redirectUri"] == ms.AL_REDIRECT
assert start["url"] == "https://anilist.co/api/v2/oauth/authorize?client_id=12345&response_type=token", start["url"]
nonce = start["nonce"]
st, page, _ = call("/al/auth/callback")
assert json.dumps(nonce) in page

# ── refusals
assert call("/al/auth/token", {"token": GOOD, "nonce": "wrong"})[0] == 403
assert call("/al/auth/token", {"token": GOOD})[0] == 403
assert call("/al/auth/token", {"token": GOOD, "nonce": nonce}, {"Origin": "https://evil.example"})[0] == 403
assert call("/al/auth/token", {"token": GOOD, "nonce": nonce}, {"Host": "evil.example"})[0] == 403
assert call("/al/auth/status", None, {"Host": "evil.example"})[0] == 403
assert call("/al/auth/status", None, {"Origin": "https://evil.example"})[0] == 403
assert not os.path.exists(ms.AL_AUTH_FILE) or "token" not in json.load(open(ms.AL_AUTH_FILE))
assert not any(t == GOOD for _, t in calls), "a refused request must not reach AniList"

# ── a token that looks wrong / that AniList rejects leaves the login open for another try
assert call("/al/auth/token", {"token": "short", "nonce": nonce})[0] == 400
st, j, _ = call("/al/auth/token", {"token": "x" * 40, "nonce": nonce})
assert st == 400 and "did not accept" in j["error"], j
assert call("/al/auth/status")[1]["loggedIn"] is False

# ── success (whitespace from a paste is fine)
st, j, h = call("/al/auth/token", {"token": "  " + GOOD + "\n", "nonce": nonce})
assert st == 200 and j["loggedIn"] is True and j["viewer"]["name"] == "Vince", j
assert j["viewer"]["avatar"] == ms.proxy_url("https://img/l.png") and j["viewer"]["scoreFormat"] == "POINT_10"
assert GOOD not in json.dumps(j), "the token must never be sent back"
assert h.get("Access-Control-Allow-Origin") is None
assert stat.S_IMODE(os.stat(ms.AL_AUTH_FILE).st_mode) == 0o600
saved = json.load(open(ms.AL_AUTH_FILE))
assert saved["viewer"]["avatar"] == "https://img/l.png"  # the file keeps the real URL
assert saved["token"] == GOOD and saved["clientId"] == "12345" and saved["expiresAt"] > time.time()
assert ms.al_token() == GOOD
assert GOOD not in call("/al/auth/status")[1].__str__()
# the nonce works once
assert call("/al/auth/token", {"token": GOOD, "nonce": nonce})[0] == 403

# ── a token that has run out is not a login
saved["expiresAt"] = int(time.time()) - 5
json.dump(saved, open(ms.AL_AUTH_FILE, "w"))
j = call("/al/auth/status")[1]
assert j["loggedIn"] is False and j["expired"] is True and ms.al_token() is None
saved["expiresAt"] = int(time.time()) + 1000
json.dump(saved, open(ms.AL_AUTH_FILE, "w"))
assert call("/al/auth/status")[1]["loggedIn"] is True

# ── AniList turning the token down (revoked) logs out, only for that token
class R:
    def __init__(self, code, data): self.status_code, self._d, self.headers = code, data, {}
    def json(self): return self._d
    def raise_for_status(self): pass
sent = []
def fake_post(url, payload, headers, timeout):
    sent.append(headers)
    return R(400, {"errors": [{"message": "Invalid token"}], "data": None})
ms._post_json = fake_post
try:
    real_request("query { Viewer { id } }", {}, "some-other-old-token")
    assert False
except ms.AniListAuthError:
    pass
assert ms.al_token() == GOOD, "a late failure of an old token must not log out the new one"
try:
    real_request("query { Viewer { id } }", {}, GOOD)
    assert False
except ms.AniListAuthError:
    pass
assert sent[-1]["Authorization"] == "Bearer " + GOOD
assert ms.al_token() is None
assert json.load(open(ms.AL_AUTH_FILE)).get("clientId") == "12345"
# and a public request sends no Authorization at all
ms._post_json = lambda *a: (sent.append(a[2]) or R(200, {"data": {"ok": 1}}))
assert real_request("query { x }", {}) == {"ok": 1} and "Authorization" not in sent[-1]

# ── log in again, then log out: the token goes, the client ID stays
ms._al_request = fake_request
nonce = call("/al/auth/start", {})[1]["nonce"]
assert call("/al/auth/token", {"token": GOOD, "nonce": nonce})[1]["loggedIn"] is True
j = call("/al/auth/logout", {})[1]
assert j["loggedIn"] is False and j["hasClientId"] is True
assert "token" not in json.load(open(ms.AL_AUTH_FILE))
# a logout also closes a login that was waiting
n2 = call("/al/auth/start", {})[1]["nonce"]
call("/al/auth/logout", {})
assert call("/al/auth/token", {"token": GOOD, "nonce": n2})[0] == 403

# ── a login left open too long can't be finished
n3 = call("/al/auth/start", {})[1]["nonce"]
ms._auth_pending["at"] -= ms.AL_PENDING_TTL + 1
assert call("/al/auth/token", {"token": GOOD, "nonce": n3})[0] == 403
assert "var nonce = \"\";" in call("/al/auth/callback")[1]

# ── the client ID can also come from the environment
os.remove(ms.AL_AUTH_FILE)
os.environ["SEKAIPOP_ANILIST_CLIENT_ID"] = "777"
assert call("/al/auth/status")[1]["hasClientId"] is True
assert "client_id=777&" in call("/al/auth/start", {})[1]["url"]

print("test_al_auth: all passed")
