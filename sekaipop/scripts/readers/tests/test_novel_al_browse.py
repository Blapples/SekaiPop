"""The novel reader's AniList Discover (novel_server/anilist.py browse / tags / info and their /al/*
routes): novels only, every filter reaches AniList as the right variable, bad values from the panel
are dropped, pages are cached, the tag list is kept in a file, the routes answer the panel only.
No network: AniList is a fake. Run: python3 tests/test_novel_al_browse.py"""
import os, sys, json, tempfile, threading, urllib.request, urllib.error, time

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="novel-al-browse-test-")
os.environ["HOME"] = TMP                                   # the data folders are made at import
sys.path.insert(0, os.path.join(HERE, "..", "novel_server"))

import anilist as al
import server

# ── a fake AniList ──────────────────────────────────────────────────────────
def media(i, title, country="JP", **kw):
    m = {"id": i, "format": "NOVEL", "status": "RELEASING", "countryOfOrigin": country, "volumes": 4,
         "chapters": None, "averageScore": 82, "genres": ["Fantasy"], "startDate": {"year": 2015},
         "title": {"romaji": title, "english": title, "native": None},
         "coverImage": {"large": "l%d" % i, "extraLarge": "x%d" % i}}
    m.update(kw)
    return m

ALL = [media(1, "Light One"), media(2, "Korean Web", "KR", volumes=None, chapters=550),
       media(3, "Light Two", averageScore=None)]
INFO = dict(media(2, "Korean Web", "KR", volumes=None, chapters=550),
            synonyms=["KW", "Korean Web"], siteUrl="https://anilist.co/manga/2",
            description="First line.<br><br>Second &amp; <i>last</i> line.<br/>(Source: x)",
            popularity=900, favourites=40, isAdult=False,
            startDate={"year": 2018, "month": 3, "day": 9}, endDate={"year": None, "month": None, "day": None},
            tags=[{"name": "Isekai", "rank": 90, "isMediaSpoiler": False, "category": "Theme-Other"},
                  {"name": "Big Twist", "rank": 99, "isMediaSpoiler": True, "category": "Theme-Other"},
                  {"name": "Magic", "rank": 70, "isMediaSpoiler": False, "category": "Theme-Fantasy"}],
            staff={"edges": [{"role": "Story", "node": {"name": {"full": "A. Writer"}}},
                             {"role": "Art", "node": {"name": {"full": "B. Artist"}}},
                             {"role": "Story & Art", "node": {"name": {"full": "A. Writer"}}}]})
MANGA = dict(INFO, id=900, format="MANGA")
CALLS = []
TAG_ROWS = [{"name": "Isekai", "category": "Theme-Other", "isAdult": False, "isGeneralSpoiler": False},
            {"name": "Ero", "category": "Sexual Content", "isAdult": True, "isGeneralSpoiler": False},
            {"name": "Spoiler", "category": "Cast", "isAdult": False, "isGeneralSpoiler": True}]
DOWN = {"on": False}


def fake(query, variables, token=None):
    CALLS.append(dict(variables))
    if DOWN["on"]:
        raise al.AlError("Could not reach AniList", 502)
    assert token is None, "Discover needs no login and must not send one"
    if "MediaTagCollection" in query:
        return {"MediaTagCollection": TAG_ROWS}
    if "Page(" in query:
        assert "format:NOVEL" in query.replace(" ", ""), "browse must ask for novels only"
        assert "type:MANGA" in query.replace(" ", "")
        return {"Page": {"pageInfo": {"hasNextPage": variables["page"] < 2, "currentPage": variables["page"]},
                         "media": ALL}}
    mid = variables["id"]
    m = {2: INFO, 900: MANGA}.get(mid)
    return {"Media": dict(m) if m else None}


al._request = fake

# ── the card ────────────────────────────────────────────────────────────────
r = al.browse()
assert [c["anilistId"] for c in r["results"]] == [1, 2, 3] and r["hasMore"] is True and r["nextPage"] == 2
c1, c2, c3 = r["results"]
assert c1["id"] == "al:1" and c1["type"] == "LIGHT NOVEL" and c1["status"] == "Releasing"
assert c1["cover"] == "x1" and c1["year"] == 2015 and c1["score"] == 82 and c1["volumes"] == 4
assert c2["type"] == "KOREAN NOVEL" and c2["chapters"] == 550 and c2["volumes"] == 0
assert c3["score"] == 0                               # no score yet is 0, not None
v = CALLS[-1]
assert v["sort"] == ["TRENDING_DESC"] and v["page"] == 1 and v["perPage"] == al.AL_PER_PAGE
assert v["adult"] is False                            # 18+ is off unless asked for
assert not any(k in v for k in ("search", "genre_in", "tag_in", "status_in", "country", "sd_gt",
                                "score_gt", "vol_gt", "ch_gt"))

# ── every filter becomes the right variable ─────────────────────────────────
al.browse(q="  dragon ", genres=["Fantasy", "Action", "Nope"], tags=["Isekai", "Isekai", "a|b", ""],
          country="KR", status="RELEASING,FINISHED,Bogus", year="2019", sort="SCORE_DESC", page=3,
          score_min=70, score_max=90, vol_min=4, vol_max=10, ch_min=100, ch_max=500, adult=True)
v = CALLS[-1]
assert v["search"] == "dragon" and v["sort"] == ["SCORE_DESC"] and v["page"] == 3
assert v["genre_in"] == ["Action", "Fantasy"]                       # unknown genre dropped, sorted
assert v["tag_in"] == ["Isekai"]                                    # repeat, a "|" and "" dropped
assert v["country"] == "KR" and v["status_in"] == ["FINISHED", "RELEASING"]
assert v["sd_gt"] == 20190000 and v["sd_lt"] == 20200000
assert v["score_gt"] == 69 and v["score_lt"] == 91                  # 7.0+ and up to 9.0, inclusive
assert v["vol_gt"] == 3 and v["vol_lt"] == 11                       # 4..10 volumes, inclusive
assert v["ch_gt"] == 99 and v["ch_lt"] == 501                       # 100..500 chapters, inclusive
assert "adult" not in v                                              # 18+ on: both allowed

# a one-sided length ("11 volumes or more", "up to 3 volumes")
al.browse(vol_min=11, genres=["Horror"]); v = CALLS[-1]
assert v["vol_gt"] == 10 and "vol_lt" not in v
al.browse(vol_max=3, genres=["Horror"]); v = CALLS[-1]
assert v["vol_lt"] == 4 and "vol_gt" not in v

# a search is ordered by best match; a plain list never is
al.browse(q="x1"); assert CALLS[-1]["sort"] == ["SEARCH_MATCH"]
al.browse(q="x2", sort="POPULARITY_DESC"); assert CALLS[-1]["sort"] == ["POPULARITY_DESC"]
al.browse(sort="SEARCH_MATCH", genres=["Comedy"]); assert CALLS[-1]["sort"] == ["TRENDING_DESC"]
al.browse(sort="DROP TABLE", genres=["Drama"]); assert CALLS[-1]["sort"] == ["TRENDING_DESC"]

# nonsense from the panel is dropped, not sent
al.browse(country="XX", year="abc", score_min="x", score_max=500, vol_min=-3, vol_max="no",
          ch_min=10**9, page="z", genres=("Mecha",)); v = CALLS[-1]
assert not any(k in v for k in ("country", "sd_gt", "score_gt", "score_lt", "vol_gt", "vol_lt", "ch_gt", "ch_lt"))
assert v["page"] == 1
# min above max is turned round, for the score and for the length
al.browse(score_min=90, score_max=70, vol_min=10, vol_max=4, genres=("Music",)); v = CALLS[-1]
assert v["score_gt"] == 69 and v["score_lt"] == 91 and v["vol_gt"] == 3 and v["vol_lt"] == 11
# at most AL_TAG_MAX tags go out
al.browse(tags=["t%d" % i for i in range(40)]); assert len(CALLS[-1]["tag_in"]) == al.AL_TAG_MAX

# a manga that slipped through is left out of the page, even if AniList sent it
ALL.append(dict(media(9, "Manga Intruder"), format="MANGA"))
r = al.browse(genres=["Sports"])
assert 9 not in [c["anilistId"] for c in r["results"]]
ALL.pop()

# ── the same page is asked for once ─────────────────────────────────────────
n = len(CALLS)
al.browse(genres=["Sports"]); al.browse(genres=["Sports"], img=lambda u: "p/" + u)
assert len(CALLS) == n, "a repeated page must come from the cache"
r = al.browse(genres=["Sports"], img=lambda u: "p/" + u)
assert r["results"][0]["image"] == "p/x1" and r["results"][0]["cover"] == "x1"
assert "image" not in al.browse(genres=["Sports"])["results"][0], "the cached page stays plain"
al.browse(genres=["Sports"], page=2); assert len(CALLS) == n + 1

# ── tags: asked for once, kept in a file, an old copy beats none ────────────
n = len(CALLS)
t = al.tags()["tags"]
assert [x["name"] for x in t] == ["Isekai", "Ero"] or [x["name"] for x in t] == ["Ero", "Isekai"]
assert all("Spoiler" != x["name"] for x in t)                       # general spoiler tags left out
assert next(x for x in t if x["name"] == "Ero")["isAdult"] is True
assert t == sorted(t, key=lambda x: (x["category"], x["name"].lower()))
saved = json.load(open(al.TAGS_FILE))
assert saved["tags"] == t and abs(saved["fetchedAt"] - time.time()) < 5
al._cache.clear()
al.tags(); assert len(CALLS) == n + 1, "the file is fresh, AniList must not be asked again"
# the file is a week old and AniList is down: the old list is used
saved["fetchedAt"] = time.time() - 8 * 86400
json.dump(saved, open(al.TAGS_FILE, "w")); al._cache.clear(); DOWN["on"] = True
assert al.tags()["tags"] == t
# no file and AniList down: an error, not an empty list
os.remove(al.TAGS_FILE); al._cache.clear()
try:
    al.tags(); raise SystemExit("no tags and no AniList must be an error")
except al.AlError as e:
    assert e.status == 502
DOWN["on"] = False

# ── one novel's page ────────────────────────────────────────────────────────
i = al.info(2)
assert i["anilistId"] == 2 and i["title"] == "Korean Web" and i["type"] == "KOREAN NOVEL"
assert i["description"] == "First line.\n\nSecond & last line.\n(Source: x)", repr(i["description"])
assert i["tags"] == ["Isekai", "Magic"], "spoiler tags are left out, the rest in rank order"
assert i["people"] == [{"name": "A. Writer", "role": "Story"}, {"name": "B. Artist", "role": "Art"}]
assert i["start"] == "2018-03-09" and i["end"] == "" and i["chapters"] == 550
assert i["names"][0] == "Korean Web" and "KW" in i["names"] and len(set(n.lower() for n in i["names"])) == len(i["names"])
assert i["siteUrl"].endswith("/manga/2") and i["score"] == 82
try:
    al.info(900); raise SystemExit("a manga must be refused")
except al.AlError as e:
    assert e.status == 400 and "not a novel" in str(e)
for bad in (0, "x", -4, None):
    try:
        al.info(bad); raise SystemExit("a bad id must be refused")
    except al.AlError as e:
        assert e.status == 400
try:
    al.info(12345); raise SystemExit("a missing title must be refused")
except al.AlError as e:
    assert e.status == 404
assert al._plain("a" * 5000).endswith("…") and len(al._plain("a b " * 2000)) <= 2401

# ── the routes ──────────────────────────────────────────────────────────────
srv = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
server.PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % server.PORT


def call(path, headers=None):
    req = urllib.request.Request(base + path, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


s, j = call("/al/browse?genres=Fantasy,Comedy&tags=Isekai|Magic&country=JP&status=RELEASING,FINISHED"
            "&year=2020&score_min=70&score_max=90&vol_min=4&vol_max=10&ch_min=1&ch_max=50"
            "&sort=SCORE_DESC&page=2&q=hero&adult=1")
assert s == 200 and len(j["results"]) == 3 and j["hasMore"] is False
assert j["results"][0]["image"].startswith("http://127.0.0.1:%d/image?url=" % server.PORT), "covers go through the image cache"
v = CALLS[-1]
assert v["genre_in"] == ["Comedy", "Fantasy"] and v["tag_in"] == ["Isekai", "Magic"] and v["country"] == "JP"
assert v["status_in"] == ["FINISHED", "RELEASING"] and v["sd_gt"] == 20200000 and v["page"] == 2
assert v["vol_gt"] == 3 and v["ch_lt"] == 51 and v["search"] == "hero" and "adult" not in v
s, j = call("/al/browse")
assert s == 200 and CALLS[-1]["sort"] == ["TRENDING_DESC"] and CALLS[-1]["adult"] is False
s, j = call("/al/tags"); assert s == 200 and {x["name"] for x in j["tags"]} == {"Isekai", "Ero"}
s, j = call("/al/info?id=2")
assert s == 200 and j["title"] == "Korean Web" and j["image"].startswith("http://127.0.0.1:")
s, j = call("/al/info?id=900"); assert s == 400 and "not a novel" in j["error"]
s, j = call("/al/info?id=zzz"); assert s == 400
DOWN["on"] = True; al._cache.clear()
s, j = call("/al/browse?genres=Horror"); assert s >= 400 and "error" in j       # AniList down is an error, not a crash
DOWN["on"] = False
# a web page (an Origin that is not this server) cannot reach any of it
for path in ("/al/browse", "/al/tags", "/al/info?id=2"):
    s, j = call(path, {"Origin": "http://evil.example"})
    assert s == 403 and j["error"] == "not allowed", (path, s, j)
srv.shutdown()
print("novel AniList browse: ok")
