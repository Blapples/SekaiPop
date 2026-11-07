"""AniList title -> WeebCentral series matching, with WeebCentral mocked.
Run: python3 tests/test_match.py"""
import os, tempfile, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

tmp = tempfile.mkdtemp()
ms.DATA_DIR = tmp
ms.MATCH_FILE = os.path.join(tmp, "anilist_matches.json")


def series(sid, title, year="2022", typ="Manhwa"):
    return {"id": f"{sid}/{title.replace(' ', '-')}", "title": title, "year": year, "type": typ,
            "status": "Ongoing", "tags": [], "image": ""}


def setup(site, aliases=None):
    """site: {query(lower): [series,...]}; aliases: {series id: [other names]}"""
    ms._cache.clear()
    log = []
    def fake_search(q, mtype=None, offset=0, sort="Latest Updates"):
        log.append((q, sort))
        return {"results": site.get(q.lower().strip(), []), "hasMore": False, "nextOffset": 0}
    def fake_fetch(url, extra_headers=None, timeout=30):
        for sid, names in (aliases or {}).items():
            if sid in url:
                li = "".join(f"<li>{n}</li>" for n in names)
                return f"<ul><li><strong>Associated Name(s)</strong><ul>{li}</ul></li></ul>"
        return "<html></html>"
    ms.search = fake_search
    ms.fetch = fake_fetch
    return log


def media(english=None, romaji=None, native=None, syn=(), year=2022, country="KR", aid=1):
    return {"id": aid, "title": {"english": english, "romaji": romaji, "native": native},
            "synonyms": list(syn), "startDate": {"year": year}, "countryOfOrigin": country}


# ── 1. the normal case still matches at once
a = series("AAA", "The Perks of Being an S-Class Heroine")
setup({"the perks of being an s-class heroine": [a]})
c = ms._wc_candidates(media("The Perks of Being an S-Class Heroine"))
assert c[0]["id"] == a["id"] and c[0]["score"] >= ms.MATCH_MIN, c

# ── 2. WeebCentral answers nothing for the full name (hyphen), but the loose one works
setup({"the perks of being an s class heroine": [a]})
c = ms._wc_candidates(media("The Perks of Being an S-Class Heroine"))
assert c and c[0]["id"] == a["id"] and c[0]["score"] >= ms.MATCH_MIN, c

# ── 3. long title with a subtitle: only the part before it is found
b = series("BBB", "Ascendance of a Bookworm", "2015", "Manga")
setup({"ascendance of a bookworm": [b]})
c = ms._wc_candidates(media("Ascendance of a Bookworm: I'll Do Anything to Become a Librarian!", year=2015, country="JP"))
assert c and c[0]["id"] == b["id"], c
assert c[0]["score"] < 1.0                              # a subtitle title is never "certain"

# ── 4. different names: WeebCentral lists the AniList name only as an associated name
d = series("DDD", "The Secretary Who Tamed the Tyrant")
setup({"i became the tyrant's secretary": [d]}, aliases={"DDD": ["Tyrant's Secretary Reborn", "I Became the Tyrant's Secretary", "폭군의 비서"]})
c = ms._wc_candidates(media("I Became the Tyrant's Secretary"))
assert c[0]["id"] == d["id"] and c[0]["score"] >= ms.MATCH_MIN and c[0].get("via") == "alias", c

# ── 5. a synonym equals the WeebCentral title
e = series("EEE", "My Dear Cold-Blooded King")
setup({"my dear cold blooded king": [e], "my dear cold-blooded king": [e]})
c = ms._wc_candidates(media("Dear Cold Blooded Prince", syn=["My Dear Cold-Blooded King"]))
assert c[0]["id"] == e["id"] and c[0]["score"] >= ms.MATCH_MIN, c

# ── 6. native (Korean) title found in the associated names
f = series("FFF", "Return of the Mad Demon")
setup({"return of the mad demon": [f], "광마회귀": [f]}, aliases={"FFF": ["광마회귀"]})
c = ms._wc_candidates(media("Return of the Mad Demon", native="광마회귀"))
assert c[0]["id"] == f["id"] and c[0]["score"] >= ms.MATCH_MIN, c
c = ms._wc_candidates(media("Mad Demon Reborn", native="광마회귀"))      # only the native name agrees
assert c[0]["id"] == f["id"] and c[0]["score"] >= ms.MATCH_MIN, c

# ── 7. a sequel / side story must NOT be taken for the original
g = series("GGG", "Solo Leveling: Ragnarok", "2024")
setup({"solo leveling": [g]})
c = ms._wc_candidates(media("Solo Leveling", year=2018))
assert not c or c[0]["score"] < ms.MATCH_MIN, c

# ── 8. same words, other order, and a bracketed note
h = series("HHH", "Villainess Reverses the Hourglass (Official)")
setup({"the villainess reverses the hourglass": [h]})
c = ms._wc_candidates(media("The Villainess Reverses the Hourglass"))
assert c[0]["id"] == h["id"] and c[0]["score"] >= ms.MATCH_MIN, c

# ── 9. nothing similar at all -> not matched, and the right "why" is logged
setup({"zzz": []})
c = ms._wc_candidates(media("A Totally Different Story"))
assert c == [], c

# ── 10. an empty answer is not kept in the cache
calls = {"n": 0}
def flaky(q, mtype=None, offset=0, sort="Latest Updates"):
    return None
ms._cache.clear()
real = ms._search
state = {"n": 0}
def fake_inner(q, t, o, s):
    state["n"] += 1
    return {"results": [] if state["n"] == 1 else [a], "hasMore": False, "nextOffset": 0}
ms._search = fake_inner
import importlib
spec2 = importlib.util.spec_from_file_location("ms2", os.path.join(HERE, "..", "manga_server.py"))
ms2 = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(ms2)
ms2._search = fake_inner
state["n"] = 0
assert ms2.search("x")["results"] == []
assert ms2.search("x")["results"] == [a]                 # asked again, not served from the cache
assert ms2.search("x")["results"] == [a]
assert state["n"] == 2                                   # ...and the good answer IS cached

# ── 11. a kept match is saved once and reused without any search
setup({"the perks of being an s-class heroine": [a]})
m1 = media("The Perks of Being an S-Class Heroine", aid=77)
got, _ = ms.al_match(m1)
assert got["id"] == a["id"] and not got["manual"]
log = setup({})
got2, _ = ms.al_match(m1)
assert got2["id"] == a["id"] and log == []

print("all match tests passed")
