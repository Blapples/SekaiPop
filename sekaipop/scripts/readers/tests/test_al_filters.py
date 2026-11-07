"""AniList browse filters (tags, several statuses, score range) and /al/tags, with AniList mocked.
Run: python3 tests/test_al_filters.py"""
import os, sys, json, tempfile, importlib.util, threading, urllib.request, time
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR = tmp; ms.TAGS_FILE = os.path.join(tmp, "al_tags.json")

calls = []
def fake(query, variables):
    calls.append((query, variables))
    if "MediaTagCollection" in query:
        return {"MediaTagCollection": [
            {"name": "Isekai", "category": "Theme-Fantasy", "isAdult": False, "isGeneralSpoiler": False},
            {"name": "Villainess", "category": "Theme-Romance", "isAdult": False, "isGeneralSpoiler": False},
            {"name": "Secret Spoiler", "category": "Theme-Drama", "isAdult": False, "isGeneralSpoiler": True},
            {"name": "Ahegao", "category": "Sexual Content", "isAdult": True, "isGeneralSpoiler": False},
        ]}
    return {"Page": {"pageInfo": {"hasNextPage": True}, "media": [
        {"id": 1, "title": {"romaji": "A"}, "coverImage": {}, "format": "MANGA", "status": "RELEASING",
         "startDate": {"year": 2020}, "averageScore": 81, "genres": ["Action"], "countryOfOrigin": "JP"}]}}
ms._al_request = fake

def last_vars(): return calls[-1][1]

# multi status + tags + score
r = ms.al_browse("", ["Action", "Nope"], "", "", "RELEASING,HIATUS,bogus", 0, "SCORE_DESC", False, 1,
                 ["Isekai", " Villainess ", "Isekai", "a|b", ""], 70, 90)
v = last_vars()
assert v["status_in"] == ["HIATUS", "RELEASING"], v
assert v["tag_in"] == ["Isekai", "Villainess"], v
assert v["genre_in"] == ["Action"], v
assert v["score_gt"] == 69 and v["score_lt"] == 91, v
assert v["adult"] is False and "status" not in v
assert r["results"][0]["score"] == 81 and r["hasMore"]

# old single status still works; no filters -> no keys
ms.al_browse("", [], "", "", "FINISHED", 0, "", True, 1)
v = last_vars(); assert v["status_in"] == ["FINISHED"] and "tag_in" not in v and "score_gt" not in v and "adult" not in v, v

# swapped / out of range scores; max 100 = no upper bound
ms.al_browse("", [], "", "", "", 0, "", False, 2, [], 90, 60)
v = last_vars(); assert v["score_gt"] == 59 and v["score_lt"] == 91, v
ms.al_browse("", [], "", "", "", 0, "", False, 3, [], 0, 100)
v = last_vars(); assert "score_gt" not in v and "score_lt" not in v, v
ms.al_browse("", [], "", "", "", 0, "", False, 4, [], 500, -4)
v = last_vars(); assert "score_gt" not in v and "score_lt" not in v, v

# cache key separates different filters
n = len(calls)
ms.al_browse("", [], "", "", "", 0, "", False, 3, ["Isekai"], 0, 0)
ms.al_browse("", [], "", "", "", 0, "", False, 3, ["Isekai"], 0, 0)
assert len(calls) == n + 1

# tags: fetched, spoilers dropped, saved, then served from file, stale copy on failure
t = ms.al_tags()["tags"]
assert [x["name"] for x in t] == ["Ahegao", "Isekai", "Villainess"] or [x["name"] for x in t][0] in ("Isekai","Ahegao"), t
assert all(x["name"] != "Secret Spoiler" for x in t)
assert os.path.exists(ms.TAGS_FILE)
ms._cache.clear(); n = len(calls)
assert ms.al_tags()["tags"] == t and len(calls) == n          # from the file
d = json.load(open(ms.TAGS_FILE)); d["fetchedAt"] = 0; json.dump(d, open(ms.TAGS_FILE, "w"))
ms._cache.clear()
def down(q, v): raise RuntimeError("down")
ms._al_request = down
assert ms.al_tags()["tags"] == t                                # stale beats nothing
os.remove(ms.TAGS_FILE); ms._cache.clear()
try: ms.al_tags(); assert False
except RuntimeError: pass

# over HTTP: query-string parsing
ms._al_request = fake; ms._cache.clear()

srv = ms.ThreadingHTTPServer(("127.0.0.1", 0), ms.Handler)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
def get(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as r:
        return json.load(r)
calls.clear(); ms._cache.clear()
out = get("/al/browse?page=2&sort=SCORE_DESC&genres=Action&tags=Isekai%7CVillainess&status=RELEASING,HIATUS&score_min=75&score_max=95&adult=0")
v = last_vars()
assert v["tag_in"] == ["Isekai", "Villainess"] and v["status_in"] == ["HIATUS", "RELEASING"], v
assert v["score_gt"] == 74 and v["score_lt"] == 96 and v["page"] == 2, v
assert out["results"][0]["title"] == "A"
out = get("/al/browse?score_min=abc&page=x")
assert last_vars()["page"] == 1 and "score_gt" not in last_vars()
assert [x["name"] for x in get("/al/tags")["tags"]]
srv.shutdown()
print("ALL OK")
