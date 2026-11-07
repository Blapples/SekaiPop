"""Series listed by volume (and mixed / extra entries) on WeebCentral, with fetch() mocked.
Run: python3 tests/test_volume_chapters.py"""
import os, json, tempfile, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ms", os.path.join(HERE, "..", "manga_server.py"))
ms = importlib.util.module_from_spec(spec); spec.loader.exec_module(ms)

# ── label parsing
cases = {
    "Volume 3": ("volume", "3"), "Vol. 3.5": ("volume", "3.5"), "Chapter 12.5": ("chapter", "12.5"),
    "Episode 4": ("chapter", "4"), "7": ("chapter", "7"), "Side Story 2": ("extra", "2"),
    "Oneshot": ("extra", "Oneshot"), "": ("chapter", ""),
}
for label, want in cases.items():
    got = ms.parse_label(label)
    assert got == want, (label, got, want)
assert ms.chapter_sort_num("Oneshot") == 0.0 and ms.chapter_sort_num("12.5") == 12.5 and ms.chapter_sort_num(None) == 0.0

# ── _info on a volume-only list (href not always the first attribute, absolute and relative links)
DETAIL = "<title>Some Series | Weeb Central</title>"
CHAPS = """
<a href="/chapters/C3"><span><span>Volume 3</span></span><time datetime="2026-03-01">x</time></a>
<a class="flex" href="https://weebcentral.com/chapters/C2"><span><span>Volume 2</span></span></a>
<a href="/chapters/C1"><span><span>Volume 1</span></span></a>
<a href="/chapters/C0"><span><span>Oneshot</span></span></a>
"""
def fake_fetch(url, extra_headers=None, timeout=30):
    return CHAPS if url.endswith("/full-chapter-list") else DETAIL
ms.fetch = fake_fetch
out = ms._info("SID/Some-Series")
chs = out["chapters"]
assert [c["id"] for c in chs] == ["C0", "C1", "C2", "C3"], chs        # oldest first
assert [c["kind"] for c in chs] == ["extra", "volume", "volume", "volume"], chs
assert [c["chapter"] for c in chs] == ["Oneshot", "1", "2", "3"], chs
assert [c["index"] for c in chs] == [0, 1, 2, 3]

# ── downloads list used to crash on float("Volume 1")
tmp = tempfile.mkdtemp(); ms.DOWNLOADS_DIR = tmp
sd = os.path.join(tmp, "SID"); os.makedirs(os.path.join(sd, "C1")); os.makedirs(os.path.join(sd, "C2"))
json.dump({"id": "SID/x", "title": "x"}, open(os.path.join(sd, "series_meta.json"), "w"))
json.dump({"chapterId": "C1", "chapterNum": "Volume 1"}, open(os.path.join(sd, "C1", "meta.json"), "w"))
json.dump({"chapterId": "C2", "chapterNum": "2"}, open(os.path.join(sd, "C2", "meta.json"), "w"))
lst = ms.dl_list()
assert [c["chapterId"] for c in lst[0]["chapters"]] == ["C2", "C1"], lst
print("ok")

# ── a title with an apostrophe: WeebCentral sends it as an HTML entity
SEARCH = ('<article><a href="/series/SID1/The-Guy"><h2>The Guy She Was Interested In '
          'Wasn&#x27;t a Guy at All</h2></a><div>Manga</div><div>2022</div><div>Ongoing</div></article>')
ms.fetch = lambda url, extra_headers=None, timeout=30: SEARCH
ms._cache.clear()
m = {"title": {"english": "The Guy She Was Interested In Wasn't a Guy at All", "romaji": "Ki ni Natteru Hito ga Otoko Janakatta"},
     "synonyms": [], "startDate": {"year": 2022}, "countryOfOrigin": "JP"}
cands = ms._wc_candidates(m)
assert cands and cands[0]["id"] == "SID1/The-Guy" and cands[0]["score"] >= ms.MATCH_MIN, cands
assert cands[0]["title"] == "The Guy She Was Interested In Wasn't a Guy at All", cands[0]["title"]
print("ok (apostrophe)")
