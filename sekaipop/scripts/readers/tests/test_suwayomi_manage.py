"""Managing Suwayomi from the panel: repositories, extensions and the sources Browse asks,
with Suwayomi mocked (no network, no Suwayomi needed). The fake keeps state, so an install
really adds sources and an uninstall really takes them away, and it can answer in the other
schema shapes a Suwayomi update could bring (flat setSettings, no `repo` field, no introspection).
Run: python3 tests/test_suwayomi_manage.py"""
import os, json, tempfile, threading, importlib.util
import urllib.request, urllib.error
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
ms._sw_up = lambda: True


class FakeSuwayomi:
    def __init__(self, wrapped=True, has_repo=True, introspect=True):
        self.wrapped, self.has_repo, self.introspect = wrapped, has_repo, introspect
        self.repos, self.calls, self.asked = [], [], []
        self.exts = {
            "eu.kanade.tachiyomi.extension.en.alpha": dict(name="Tachiyomi: Alpha", lang="en", versionName="1.4.1", installed=False, update=False, nsfw=False, sources=[("10", "Alpha Reader")]),
            "eu.kanade.tachiyomi.extension.en.zeta":  dict(name="Tachiyomi: Zeta",  lang="en", versionName="1.4.7", installed=True,  update=True,  nsfw=False, sources=[("30", "Zeta Scans")]),
            "eu.kanade.tachiyomi.extension.fr.fran":  dict(name="Tachiyomi: Fran",  lang="fr", versionName="1.4.2", installed=False, update=False, nsfw=False, sources=[("50", "Francais")]),
            "eu.kanade.tachiyomi.extension.all.spicy": dict(name="Tachiyomi: Spicy", lang="all", versionName="1.4.3", installed=False, update=False, nsfw=True, sources=[("40", "Spicy")]),
        }

    def sources(self):
        return [{"id": i, "name": n, "lang": e["lang"], "supportsLatest": True, "isNsfw": e["nsfw"]}
                for e in self.exts.values() if e["installed"] for i, n in e["sources"]]

    def ext_rows(self, query):
        rows = []
        for pkg, e in self.exts.items():
            r = {"pkgName": pkg, "name": e["name"], "lang": e["lang"], "versionName": e["versionName"],
                 "isInstalled": e["installed"], "hasUpdate": e["update"], "isObsolete": False,
                 "isNsfw": e["nsfw"], "iconUrl": f"/api/v1/extension/icon/{pkg}.apk"}
            if self.has_repo:
                r["repo"] = "https://example.invalid/index.min.json"
            rows.append(r)
        return rows

    def gql(self, query, variables=None, timeout=60):
        v = variables or {}
        self.calls.append(query.split("(")[0].split("{")[0].strip() or query[:30])
        if "__type(name" in query:
            if not self.introspect:
                raise RuntimeError("introspection is disabled")
            if v["n"] == "ExtensionType":
                names = ["pkgName", "name", "lang", "versionName", "isInstalled", "hasUpdate", "isObsolete", "isNsfw", "iconUrl"]
                return {"__type": {"fields": [{"name": n} for n in names + (["repo"] if self.has_repo else [])], "inputFields": None}}
            if v["n"] == "SetSettingsInput":
                names = ["clientMutationId", "settings"] if self.wrapped else ["clientMutationId", "extensionRepos"]
                return {"__type": {"fields": None, "inputFields": [{"name": n} for n in names]}}
            return {"__type": None}
        if "setSettings" in query:
            if ("{settings:" in query) != self.wrapped:
                raise RuntimeError("Validation error: unknown field in setSettings input")
            self.repos = list(v["r"])
            return {"setSettings": {"settings": {"extensionRepos": self.repos}}}
        if query.startswith("query { settings"):
            return {"settings": {"extensionRepos": list(self.repos)}}
        if "fetchExtensions" in query:
            assert self.has_repo or " repo" not in query, "asked for a field this Suwayomi has not got"
            if not self.repos:
                raise RuntimeError("no extension repositories are set")
            return {"fetchExtensions": {"extensions": self.ext_rows(query)}}
        if "updateExtension" in query:
            e = self.exts[v["id"]]
            patch = v["patch"]
            if patch.get("install"):
                e["installed"] = True
            if patch.get("uninstall"):
                e["installed"] = False
            if patch.get("update"):
                e["update"] = False
            return {"updateExtension": {"extension": {"pkgName": v["id"], "isInstalled": e["installed"], "hasUpdate": e["update"]}}}
        if "extensions { nodes" in query:
            assert self.has_repo or " repo" not in query
            return {"extensions": {"nodes": self.ext_rows(query)}}
        if "sources { nodes" in query:
            return {"sources": {"nodes": self.sources()}}
        if "fetchSourceManga" in query:
            src = v["input"]["source"]
            self.asked.append(src)
            return {"fetchSourceManga": {"hasNextPage": False, "mangas": [
                {"id": int(src) * 100 + 1, "title": f"Series from {src}", "thumbnailUrl": None, "status": "ONGOING",
                 "genre": []}]}}
        raise AssertionError("unexpected query " + query[:70])


def use(fake):
    ms._cache.clear(); ms._sw_types.clear()
    ms.sw_choice_set(None)
    ms.sw_gql = fake.gql
    return fake


# ── 1. extensions: listed with what the panel needs; installed first, updates before the rest
fake = use(FakeSuwayomi())
ms.sw_repos_set(["https://example.invalid/index.min.json"])
d = ms.sw_extensions()
assert [r["pkg"].rsplit(".", 1)[1] for r in d["extensions"]] == ["zeta", "alpha", "fran", "spicy"], d
z = d["extensions"][0]
assert z["installed"] and z["update"] and z["version"] == "1.4.7" and z["lang"] == "en" and z["repo"], z
assert z["icon"].startswith("http://127.0.0.1:") and "/image?url=" in z["icon"], z["icon"]         # through the image proxy
assert d["langs"] == ["all", "en", "fr"] and d["lang"] == "en", d
assert ms.sw_extensions(refresh=True)["extensions"], "refresh answers like the list"
fake.repos = []
try:
    ms.sw_extensions(refresh=True); raise SystemExit("a refresh with no repository should say so")
except RuntimeError as e:
    assert "repositor" in str(e)

# ── 2. repositories: add / remove / dedupe / only web addresses
fake = use(FakeSuwayomi())
assert ms.sw_repos_get()["repos"] == [] and ms.sw_repos_get()["suggested"][0]["name"] == "Keiyoushi"
r = ms.sw_repos_change(add="https://raw.example/a/index.min.json")
assert r["repos"] == ["https://raw.example/a/index.min.json"], r
r = ms.sw_repos_change(add="https://raw.example/b/index.min.json")
r = ms.sw_repos_change(add=" https://raw.example/a/index.min.json ")          # the same one, with spaces
assert r["repos"] == ["https://raw.example/a/index.min.json", "https://raw.example/b/index.min.json"], r
r = ms.sw_repos_change(remove="https://raw.example/a/index.min.json")
assert r["repos"] == ["https://raw.example/b/index.min.json"], r
for bad in ("file:///etc/passwd", "javascript:alert(1)", "not a url", "ftp://x/y"):
    try:
        ms.sw_repos_change(add=bad); raise SystemExit("accepted " + bad)
    except ValueError:
        pass
assert ms.sw_repos_get()["repos"] == ["https://raw.example/b/index.min.json"]

# ── 3. the other schema shapes: flat setSettings, no `repo` field, no introspection at all
for kw in (dict(wrapped=False), dict(has_repo=False), dict(introspect=False), dict(wrapped=False, introspect=False, has_repo=False)):
    fake = use(FakeSuwayomi(**kw))
    assert ms.sw_repos_change(add="https://raw.example/x/index.min.json")["repos"] == ["https://raw.example/x/index.min.json"], kw
    rows = ms.sw_extensions()["extensions"]
    assert len(rows) == 4 and (rows[0]["repo"] != "" if kw.get("has_repo", True) and kw.get("introspect", True) else True), kw

# ── 4. install / update / uninstall: the sources follow, and so does a pick
fake = use(FakeSuwayomi())
base_names = lambda: [s["name"] for s in ms._sw_sources()]
assert base_names() == ["Zeta Scans"]
res = ms.sw_ext_action("install", "eu.kanade.tachiyomi.extension.en.alpha")
assert res["ok"] and res["newSources"] == ["Alpha Reader"], res
assert base_names() == ["Alpha Reader", "Zeta Scans"], "the sources list is cached for 10 minutes: an install must drop it"
res = ms.sw_ext_action("update", "eu.kanade.tachiyomi.extension.en.zeta")
assert fake.exts["eu.kanade.tachiyomi.extension.en.zeta"]["update"] is False
res = ms.sw_ext_action("uninstall", "eu.kanade.tachiyomi.extension.en.alpha")
assert base_names() == ["Zeta Scans"]
for bad in (("remove", "eu.kanade.x"), ("install", "x; drop"), ("install", ""), ("install", "a b")):
    try:
        ms.sw_ext_action(*bad); raise SystemExit("accepted " + repr(bad))
    except ValueError:
        pass

# update all: only the installed ones that have an update
fake = use(FakeSuwayomi())
fake.exts["eu.kanade.tachiyomi.extension.en.alpha"]["update"] = True          # not installed: left alone
r = ms.sw_ext_update_all()
assert r["updated"] == ["eu.kanade.tachiyomi.extension.en.zeta"] and r["failed"] == [] and r["ok"], r
assert fake.exts["eu.kanade.tachiyomi.extension.en.alpha"]["update"] is True

# ── 5. the sources: a pick is exactly what Browse asks, any language, and installs keep it whole
fake = use(FakeSuwayomi())
for pkg in fake.exts:
    fake.exts[pkg]["installed"] = True
v = ms.sw_sources_view()
assert [(s["name"], s["used"]) for s in v["sources"]] == [("Alpha Reader", True), ("Francais", False), ("Spicy", False), ("Zeta Scans", True)], v
assert v["custom"] is False
v = ms.sw_source_use("50", True)                                              # a French source, on purpose
assert v["custom"] is True and [n["name"] for n in ms._sw_sources()] == ["Alpha Reader", "Zeta Scans", "Francais"], v
assert json.load(open(os.path.join(tmp, "sw_sources.json")))["sources"] == ["10", "30", "50"]
v = ms.sw_source_use("10", False)
assert [n["name"] for n in ms._sw_sources()] == ["Zeta Scans", "Francais"]
v = ms.sw_source_use("40", True)                                              # an 18+ source, on purpose too
assert "Spicy" in [n["name"] for n in ms._sw_sources()]
for bad in (("999", True), ("x1", True), ("", True)):
    try:
        ms.sw_source_use(*bad); raise SystemExit("accepted " + repr(bad))
    except ValueError:
        pass
# a source installed later joins a pick; an uninstalled one leaves it
fake.exts["eu.kanade.tachiyomi.extension.en.alpha"]["installed"] = False
ms._sw_forget()
ms.sw_ext_action("install", "eu.kanade.tachiyomi.extension.en.alpha")
assert ms.sw_choice_get()[-1] == "10", ms.sw_choice_get()
ms.sw_ext_action("uninstall", "eu.kanade.tachiyomi.extension.fr.fran")
assert "50" not in ms.sw_choice_get(), ms.sw_choice_get()
# the last one cannot be taken out
fake = use(FakeSuwayomi())
ms.sw_source_use("30", True)
try:
    ms.sw_source_use("30", False); raise SystemExit("emptied the pick")
except ValueError as e:
    assert "at least one" in str(e)
# automatic again
v = ms.sw_sources_auto()
assert v["custom"] is False and not os.path.exists(os.path.join(tmp, "sw_sources.json"))
# a pick whose sources are all gone falls back to the automatic choice instead of breaking Browse
fake = use(FakeSuwayomi())
ms.sw_source_use("30", True)
fake.exts["eu.kanade.tachiyomi.extension.en.zeta"]["installed"] = False
fake.exts["eu.kanade.tachiyomi.extension.en.alpha"]["installed"] = True
ms._sw_forget()
assert [n["name"] for n in ms._sw_sources()] == ["Alpha Reader"]
# a damaged pick file is ignored
open(os.path.join(tmp, "sw_sources.json"), "w").write("{not json")
assert ms.sw_choice_get() is None
ms.sw_choice_set(None)

# ── 5b. one source on its own: the panel's per-source keys narrow Latest and search to it
fake = use(FakeSuwayomi())
for pkg in fake.exts:
    fake.exts[pkg]["installed"] = True
ms._sw_focus["id"] = ""
assert ms.sw_sources_view()["focus"] == ""
fake.asked.clear()
rows = ms.sw_latest(1)["results"]
assert sorted(fake.asked) == ["10", "30"] and {r["type"] for r in rows} == {"Alpha Reader", "Zeta Scans"}, (fake.asked, rows)
v = ms.sw_focus_set("30")
assert v["focus"] == "30", v
fake.asked.clear()
rows = ms.sw_latest(1)["results"]                     # not the cached list of all the sources
assert fake.asked == ["30"] and {r["type"] for r in rows} == {"Zeta Scans"}, (fake.asked, rows)
fake.asked.clear()
ms.sw_search("anything")
assert fake.asked == ["30"], fake.asked
v = ms.sw_focus_set("10")                             # another source: its own list, not the last one's
fake.asked.clear()
assert {r["type"] for r in ms.sw_latest(1)["results"]} == {"Alpha Reader"} and fake.asked == ["10"]
for bad in ("50", "x1", "999"):                       # not picked / not an id / not installed
    try:
        ms.sw_focus_set(bad); raise SystemExit("focused on " + repr(bad))
    except ValueError:
        pass
assert ms.sw_sources_view()["focus"] == "10"
v = ms.sw_focus_set("")                               # all of them again (the list of all is still cached)
rows = ms.sw_latest(1)["results"]
assert v["focus"] == "" and {r["type"] for r in rows} == {"Alpha Reader", "Zeta Scans"}, (v, rows)
# taking the focused source out of the pick drops the focus; so does a pick that no longer has it
ms.sw_focus_set("30")
ms.sw_source_use("30", False)
assert ms._sw_focus["id"] == "" and ms.sw_sources_view()["focus"] == ""
ms.sw_source_use("30", True)
ms.sw_focus_set("30")
ms.sw_sources_auto()                                  # 30 is picked by the automatic choice too: still focused
fake.asked.clear()
ms.sw_search("x")
assert fake.asked == ["30"], fake.asked
ms._sw_focus["id"] = ""

# ── 6. the HTTP side: local only, off when Suwayomi is not set up, errors that say what is wrong
fake = use(FakeSuwayomi())
ms.sw_repos_set(["https://example.invalid/index.min.json"])
srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{port}"

def call(path, data=None, headers=None):
    req = urllib.request.Request(base + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers=headers or {})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"null"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null"), e.headers

st, b, h = call("/sw/status")
assert st == 200 and b["enabled"] and b["running"] and b["custom"] is False and "Access-Control-Allow-Origin" not in h, (st, b)
st, b, _ = call("/sw/extensions")
assert st == 200 and len(b["extensions"]) == 4
st, b, _ = call("/sw/extensions?refresh=1")
assert st == 200 and len(b["extensions"]) == 4
assert call("/sw/repos")[1]["repos"] == ["https://example.invalid/index.min.json"]
st, b, _ = call("/sw/repos", {"add": "https://raw.example/c/index.min.json"})
assert st == 200 and b["repos"][-1] == "https://raw.example/c/index.min.json"
st, b, _ = call("/sw/repos", {"add": "file:///etc/passwd"})
assert st == 400 and "web address" in b["error"], (st, b)
st, b, _ = call("/sw/ext", {"action": "install", "pkg": "eu.kanade.tachiyomi.extension.en.alpha"})
assert st == 200 and b["newSources"] == ["Alpha Reader"], (st, b)
st, b, _ = call("/sw/ext", {"action": "install", "pkg": "a b"})
assert st == 400, (st, b)
st, b, _ = call("/sw/ext", {"action": "update-all"})
assert st == 200 and b["ok"], (st, b)
st, b, _ = call("/sw/sources")
assert st == 200 and [s["name"] for s in b["sources"] if s["used"]] == ["Alpha Reader", "Zeta Scans"], b
st, b, _ = call("/sw/sources", {"id": "30", "use": False})
assert st == 200 and b["custom"] and [s["name"] for s in b["sources"] if s["used"]] == ["Alpha Reader"], b
st, b, _ = call("/sw/sources", {"id": "10", "use": False})
assert st == 400 and "at least one" in b["error"], (st, b)
st, b, _ = call("/sw/sources", {"auto": True})
assert st == 200 and b["custom"] is False
st, b, _ = call("/sw/sources", {"focus": "30"})
assert st == 200 and b["focus"] == "30", (st, b)
st, b, _ = call("/sw/sources", {"focus": "999"})
assert st == 400, (st, b)
st, b, _ = call("/sw/sources", {"focus": ""})
assert st == 200 and b["focus"] == "", (st, b)
assert call("/sw/nothing")[0] == 404 and call("/sw/nothing", {})[0] == 404
# another host name (DNS rebinding) or another origin is refused
assert call("/sw/status", headers={"Host": "evil.example"})[0] == 403
assert call("/sw/ext", {"action": "install", "pkg": "x.y"}, headers={"Origin": "http://evil.example"})[0] == 403
assert call("/sw/sources", {"auto": True}, headers={"Origin": "https://evil.example"})[0] == 403
# not set up: status says so, the rest is a clear 400
ms.SW_ENABLED = False
st, b, _ = call("/sw/status")
assert st == 200 and b["enabled"] is False and b["running"] is False
st, b, _ = call("/sw/extensions")
assert st == 400 and "not set up" in b["error"], (st, b)
assert call("/sw/ext", {"action": "install", "pkg": "x.y"})[0] == 400
ms.SW_ENABLED = True
srv.shutdown()

print("test_suwayomi_manage: ok")
