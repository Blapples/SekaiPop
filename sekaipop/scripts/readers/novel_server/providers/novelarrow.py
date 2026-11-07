# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
NovelArrow provider  –  https://novelping.com
Ported from the LNReader "Novel Arrow" plugin (lnreader-plugins, v1.0.1).

novelarrow.com now sits behind a Cloudflare managed challenge that only a
real browser passes, and past it just redirects to novelping.com — the same
site and the same /api-web backend, reachable without the challenge. The
plugin's /novels/… and /novel/… routes are gone there; pages now live under
/book/…, so the lists are scraped from the current routes:
  - hot()      → /sort/popular
  - latest()   → /sort/updates?page=N
  - search()   → /search?keyword=<query>&page=N
  - info()     → /book/<slug>  +  /api-web/novels/<slug>/chapters?sort=asc
  - chapter()  → /api-web/novels/<slug>/chapters/<chapter-id>

IDs (raw, before the registry prefixes them):
  novel    "<slug>"                 e.g. "shadow-slave"
  chapter  "<slug>/<chapter-id>"    e.g. "shadow-slave/chapter-1-nightmare-begins"
"""

import re
from urllib.parse import quote

from .base import NovelProvider
from .utils import fetch, fetch_json, fetch_bytes, cached, clean_text

BASE = "https://novelping.com"

TTL_HOT    = 300
TTL_LATEST = 120
TTL_SEARCH = 600
TTL_INFO   = 1800
TTL_CHAP   = 86400

# Chapter reads would otherwise count towards the account-less reading
# progress the site tracks; the plugin turns it off the same way.
CHAPTER_HEADERS = {"x-track-reading-progress": "false"}


def _meta(html: str, prop: str) -> str:
    m = re.search(rf'<meta[^>]+(?:property|name)="{re.escape(prop)}"[^>]*content="([^"]*)"', html)
    return clean_text(m.group(1)) if m else ""


def _status(s: str) -> str:
    s = s.lower()
    return "Ongoing" if "ongoing" in s else "Completed" if "complete" in s else ""


class NovelArrowProvider(NovelProvider):
    name  = "novelarrow"
    label = "NovelArrow"

    def _key(self, *parts) -> str:
        return f"{self.name}:" + ":".join(str(p) for p in parts)

    @staticmethod
    def _proxy(img_url: str, port: int = 5151) -> str:
        if not img_url:
            return ""
        full = img_url if img_url.startswith("http") else BASE + img_url
        return f"http://127.0.0.1:{port}/image?url={quote(full, safe='')}"

    # ── List pages ────────────────────────────────────────────────────────
    # Every list (popular, updates, search) uses the same row:
    #   <div class="row"> <img src=cover> <h3 class="novel-title"><a href=/book/slug>
    #   <span class="author">…</span> … <span class="chapter-title">latest</span>

    def _parse_rows(self, html: str) -> list:
        results, seen = [], set()
        for block in re.split(r'<div class="row">', html)[1:]:
            link_m = re.search(
                r'class="novel-title"><a href="[^"]*/book/([^"/?#]+)"[^>]*>([\s\S]*?)</a>', block)
            if not link_m or link_m.group(1) in seen:
                continue
            slug = link_m.group(1)
            seen.add(slug)
            img_m    = re.search(r'<img[^>]+src="([^"]+)"', block)
            author_m = re.search(r'class="author">([\s\S]*?)</span>\s*</div>', block)
            chap_m   = re.search(r'class="[^"]*chapter-title[^"]*">([\s\S]*?)</span>', block)
            results.append({
                "id":            slug,
                "title":         clean_text(link_m.group(2)),
                "image":         self._proxy(img_m.group(1)) if img_m else "",
                "author":        clean_text(author_m.group(1)) if author_m else "",
                "latestChapter": clean_text(chap_m.group(1)) if chap_m else "",
            })
        return results

    @staticmethod
    def _has_next(html: str) -> bool:
        # The "»" item is present on every page; on the last it's disabled.
        m = re.search(r'<li class="next([^"]*)"', html)
        return bool(m) and "disabled" not in m.group(1)

    def _page(self, path: str, page: int) -> dict:
        sep  = "&" if "?" in path else "?"
        html = fetch(f"{BASE}{path}{sep}page={page}" if page > 1 else BASE + path)
        return {
            "results":  self._parse_rows(html),
            "hasMore":  self._has_next(html),
            "nextPage": page + 1,
        }

    # ── NovelProvider interface ───────────────────────────────────────────

    def hot(self) -> list:
        return cached(self._key("hot"), TTL_HOT,
                      lambda: self._page("/sort/popular", 1)["results"])

    def latest(self, page: int = 1) -> dict:
        return cached(self._key("latest", page), TTL_LATEST,
                      lambda: self._page("/sort/updates", page))

    def search(self, query, genre=None, status="All", page=1) -> dict:
        # The site's search has no genre or status filter.
        return cached(self._key("search", query, page), TTL_SEARCH,
                      lambda: self._page(f"/search?keyword={quote(query)}", page))

    def info(self, novel_id: str) -> dict:
        return cached(self._key("info", novel_id), TTL_INFO, lambda: self._info(novel_id))

    def chapter(self, chapter_id: str) -> dict:
        return cached(self._key("chapter", chapter_id), TTL_CHAP,
                      lambda: self._chapter(chapter_id))

    def fetch_image(self, url: str) -> tuple[bytes, str]:
        return fetch_bytes(url)

    # ── Detail + chapter list ─────────────────────────────────────────────

    def _info(self, slug: str) -> dict:
        html = fetch(f"{BASE}/book/{quote(slug)}")

        desc_m = re.search(
            r'id="novel-description-content"[^>]*>([\s\S]*?)</div>', html)
        if desc_m:
            paras = [clean_text(p) for p in
                     re.findall(r'<p[^>]*>([\s\S]*?)</p>', desc_m.group(1))]
            description = "\n\n".join(p for p in paras if p) or clean_text(desc_m.group(1))
        else:
            description = _meta(html, "og:description")

        genres = [g.strip().title() for g in _meta(html, "og:novel:genre").split(",")
                  if g.strip()]

        data = fetch_json(f"{BASE}/api-web/novels/{quote(slug)}/chapters?sort=asc")
        chapters, numbers = [], []
        for c in data.get("items") or []:
            cid = c.get("chapter_id")
            if not cid:
                continue
            title = clean_text(c.get("chapter_name") or "")
            num_m = re.match(r'(?:chapter|ch\.?)\s*(\d+(?:\.\d+)?)', title, re.I) \
                 or re.match(r'chapter-(\d+)', cid)
            numbers.append(num_m.group(1) if num_m else None)
            chapters.append({"id": f"{slug}/{cid}", "title": title or cid})

        # The reader orders chapters by this number, while the API's list is
        # already in reading order. Titles' own numbers are kept when they run
        # strictly upwards; restarts, gaps in numbering ("027-the-worth-of-
        # words") or repeats fall back to the position in the list.
        values = [float(n) if n else None for n in numbers]
        ordered = all(v is not None for v in values) and \
                  all(a < b for a, b in zip(values, values[1:]))
        for i, c in enumerate(chapters):
            c["chapter"] = numbers[i] if ordered else str(i + 1)

        return {
            "id":          slug,
            "title":       _meta(html, "og:novel:novel_name")
                           or _meta(html, "og:title").replace(" | NovelPing", ""),
            "description": description,
            "status":      _status(_meta(html, "og:novel:status")),
            "author":      _meta(html, "og:novel:author"),
            "image":       self._proxy(_meta(html, "og:image")),
            "genres":      genres,
            "chapters":    chapters,
        }

    # ── Chapter content ───────────────────────────────────────────────────
    # chapter_content is HTML: an <h4> title, then <p> paragraphs.

    def _chapter(self, chapter_id: str) -> dict:
        slug, _, cid = chapter_id.partition("/")
        data = fetch_json(f"{BASE}/api-web/novels/{quote(slug)}/chapters/{quote(cid)}",
                          CHAPTER_HEADERS)
        info = (data.get("item") or {}).get("chapterInfo") or {}
        body = info.get("chapter_content") or ""

        paragraphs = [t for t in (clean_text(p) for p in
                                  re.findall(r'<p[^>]*>([\s\S]*?)</p>', body)) if t]
        if not paragraphs and body:
            # Content without <p> markup: one paragraph per line.
            body = re.sub(r'<h4[^>]*>[\s\S]*?</h4>', "", body)
            paragraphs = [t for t in (clean_text(line) for line in
                                      re.split(r'<br\s*/?>|\n', body)) if t]
        if not paragraphs:
            paragraphs = ["This chapter is premium or unavailable on NovelArrow."]

        prev_c = (info.get("prevChapter") or {}).get("chapter_id")
        next_c = (info.get("nextChapter") or {}).get("chapter_id")
        return {
            "id":         chapter_id,
            "title":      clean_text(info.get("chapter_name") or ""),
            "paragraphs": paragraphs,
            "wordCount":  sum(len(p.split()) for p in paragraphs),
            "prevId":     f"{slug}/{prev_c}" if prev_c else "",
            "nextId":     f"{slug}/{next_c}" if next_c else "",
        }
