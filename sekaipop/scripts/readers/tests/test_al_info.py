"""The info block of a title's page: status in plain words, all genres and tags (spoilers marked),
the other names, the release dates, what AniList knows about the translation, and the ratings.
Pure functions of AniList's reply, so nothing is mocked but the reply itself.
Run: python3 tests/test_al_info.py"""
import os, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

M = {
    "id": 7, "title": {"romaji": "Ore dake Level Up na Ken", "english": "Solo Leveling", "native": "나 혼자만 레벨업"},
    "synonyms": ["Only I Level Up", "I Level Up Alone", "solo leveling", "Ore dake Level Up na Ken"],
    "coverImage": {"large": "", "extraLarge": ""}, "format": "MANGA", "status": "FINISHED",
    "startDate": {"year": 2018, "month": 3, "day": 4}, "endDate": {"year": 2021, "month": 12, "day": None},
    "averageScore": 85, "meanScore": 86, "popularity": 250000, "favourites": 91000,
    "genres": ["Action", "Adventure", "Fantasy"], "countryOfOrigin": "KR",
    "chapters": 200, "volumes": 14, "siteUrl": "https://anilist.co/manga/7", "isLicensed": True,
    "description": "A weak hunter<br>levels up.",
    "externalLinks": [
        {"site": "Tapas", "url": "https://tapas.io/x", "type": "STREAMING", "language": "English"},
        {"site": "Webtoon", "url": "https://webtoons.com/x", "type": "STREAMING", "language": "English"},
        {"site": "Tapas", "url": "https://tapas.io/y", "type": "STREAMING", "language": "English"},
        {"site": "Kakao Page", "url": "https://page.kakao.com/x", "type": "STREAMING", "language": "Korean"},
        {"site": "Official Site", "url": "https://x", "type": "INFO", "language": "English"},
    ],
    "tags": [
        {"name": "Male Protagonist", "rank": 70, "isMediaSpoiler": False, "category": "Cast-Main Cast"},
        {"name": "Dungeon", "rank": 91, "isMediaSpoiler": False, "category": "Setting-Scene"},
        {"name": "Death Game", "rank": 40, "isMediaSpoiler": True, "category": "Theme-Other"},
        {"name": "Necromancy", "rank": 91, "isMediaSpoiler": False, "category": "Theme-Fantasy"},
    ],
    "staff": {"edges": []},
}

b = ms._al_base(M)
assert b["status"] == "Finished" and b["statusLabel"] == "Completed", b
assert b["genres"] == ["Action", "Adventure", "Fantasy"]
# every tag, best first (ties by name), the spoiler one marked, nothing dropped
assert [t["name"] for t in b["tagList"]] == ["Dungeon", "Necromancy", "Male Protagonist", "Death Game"], b["tagList"]
assert b["tagList"][-1]["spoiler"] is True and b["tagList"][0]["spoiler"] is False
assert b["tagList"][0]["category"] == "Setting-Scene" and b["tagList"][0]["rank"] == 91
assert b["tags"][:3] == ["Action", "Adventure", "Fantasy"], "the hero's short line is unchanged"
# the other names: not the shown one, no repeats whatever the case, native kept
assert b["title"] == "Solo Leveling"
assert b["altNames"] == ["Ore dake Level Up na Ken", "나 혼자만 레벨업", "Only I Level Up", "I Level Up Alone"], b["altNames"]
# dates
assert (b["year"], b["endYear"]) == (2018, 2021)
assert b["startDate"] == "Mar 4, 2018" and b["endDate"] == "Dec 2021", (b["startDate"], b["endDate"])
# ratings
assert (b["score"], b["meanScore"], b["popularity"], b["favourites"]) == (85, 86, 250000, 91000)
assert (b["chaptersTotal"], b["volumesTotal"]) == (200, 14) and b["siteUrl"].endswith("/7")
# translation: English read-online links make it official; one site once; Korean / INFO links don't count
t = b["translation"]
assert t["original"] == "Korean" and t["kind"] == "official" and t["licensed"] is True, t
assert [x["site"] for x in t["sites"]] == ["Tapas", "Webtoon"], t
assert t["label"] == "Official English \u00b7 Tapas, Webtoon", t["label"]
assert b["chapters"] == [] and b["id"] == "" and b["anilistId"] == 7      # the shape al_detail relies on

# licensed, but no English link: says so, and does not claim an official English release
M2 = dict(M, externalLinks=[], countryOfOrigin="JP", status="RELEASING", endDate=None)
t2 = ms._al_base(M2)["translation"]
assert t2["kind"] == "licensed" and t2["original"] == "Japanese" and "official English" not in t2["label"].lower(), t2
b2 = ms._al_base(M2)
assert b2["statusLabel"] == "Ongoing" and b2["endDate"] == "" and b2["endYear"] == 0

# not licensed: a fan translation
t3 = ms._al_base(dict(M, externalLinks=None, isLicensed=False, countryOfOrigin="CN"))["translation"]
assert t3["kind"] == "fan" and t3["original"] == "Chinese" and t3["sites"] == [], t3
t4 = ms._al_base(dict(M, externalLinks=None, isLicensed=None))["translation"]
assert t4["kind"] == "fan", "an unknown licence flag is not a licence"

# a bare title: nothing breaks, nothing is invented
bare = ms._al_base({"id": 9, "title": {"romaji": "X"}, "tags": None, "genres": None, "synonyms": None})
assert bare["altNames"] == [] and bare["tagList"] == [] and bare["genres"] == []
assert bare["startDate"] == "" and bare["endDate"] == "" and bare["statusLabel"] == ""
assert bare["translation"]["original"] == "" and bare["translation"]["kind"] == "fan"
assert (bare["meanScore"], bare["popularity"], bare["favourites"], bare["chaptersTotal"]) == (0, 0, 0, 0)

# dates with parts missing
assert ms._al_date({"year": 2020}) == "2020" and ms._al_date({"year": 2020, "month": 5}) == "May 2020"
assert ms._al_date({"month": 5, "day": 1}) == "" and ms._al_date(None) == ""

# the media query asks for what the block shows
q = ms._AL_MEDIA_Q
for f in ("endDate", "isLicensed", "externalLinks", "meanScore", "popularity", "favourites", "category", "startDate{year month day}"):
    assert f in q, f
assert "score100:score(format:POINT_100)" in ms._AL_ENTRY_FIELDS

# al_detail (what /al/info sends) carries all of it, with and without a WeebCentral match, as JSON
import json
ms.al_media = lambda aid: M
ms.al_match = lambda m, provider=None: (None, [])
d = ms.al_detail(7)
assert d["unmatched"] is True and d["translation"]["kind"] == "official" and d["tagList"] and d["altNames"], d
ms.al_match = lambda m, provider=None: ({"id": "S1/Solo", "title": "Solo Leveling", "manual": False, "score": 1.0}, [])
ms.info = lambda i: {"chapters": [{"id": "c1", "chapter": "1"}], "description": "x", "authors": ["Y"], "image": "z"}
d = ms.al_detail(7)
assert d["id"] == "S1/Solo" and len(d["chapters"]) == 1 and d["statusLabel"] == "Completed" and d["siteUrl"], d
json.dumps(d)

print("test_al_info: all passed")
