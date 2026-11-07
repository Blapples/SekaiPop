# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
Chikari provider  –  https://chikari.moe
Ported from the LNReader "Chikari" plugin (lnreader-plugins, v1.0.1).

The site is backed by a JSON API, so nothing here scrapes HTML:
  - hot()      → /api/novels?sort=popular
  - latest()   → /api/novels?sort=updated
  - search()   → /api/novels?sort=popular&q=<query>[&genre=<slug>]
  - info()     → /api/novels/<slug>  +  /api/novels/<slug>/chapters (paged)
  - chapter()  → /api/novels/<slug>/chapters/<number>/read

IDs (raw, before the registry prefixes them):
  novel    "<slug>"                 e.g. "shadow-slave"
  chapter  "<slug>/<number>"        e.g. "shadow-slave/12" or "…/12.5"
"""

import re
from urllib.parse import quote

from .base import NovelProvider
from .utils import fetch_json, fetch_bytes, cached, clean_text

BASE = "https://chikari.moe"

TTL_HOT    = 300
TTL_LATEST = 120
TTL_SEARCH = 600
TTL_INFO   = 1800
TTL_CHAP   = 86400

PAGE_SIZE    = 60      # list pages, as the plugin requests them
SEARCH_SIZE  = 36
CHAPTER_PAGE = 500     # the API's largest chapter-list page


def _num(n) -> str:
    """Chapter numbers arrive as floats: 12.0 → "12", 12.5 → "12.5"."""
    try:
        f = float(n)
    except (TypeError, ValueError):
        return str(n or "")
    return str(int(f)) if f.is_integer() else str(f)


def _status(s: str) -> str:
    return "Ongoing" if s == "releasing" else "Completed" if s else ""


def _chapter_title(title: str, number: str) -> str:
    # Many titles repeat the number: "Chapter 1 - 1: Nightmare Begins".
    title = clean_text(title or "")
    if not title:
        return f"Chapter {number}"
    return re.sub(rf"^Chapter {re.escape(number)} - {re.escape(number)}\b",
                  f"Chapter {number}", title)


class ChikariProvider(NovelProvider):
    name  = "chikari"
    label = "Chikari"

    def _key(self, *parts) -> str:
        return f"{self.name}:" + ":".join(str(p) for p in parts)

    @staticmethod
    def _proxy(img_url: str, port: int = 5151) -> str:
        if not img_url:
            return ""
        return f"http://127.0.0.1:{port}/image?url={quote(img_url, safe='')}"

    def _card(self, item: dict) -> dict:
        latest = item.get("latest_chapter")
        return {
            "id":            item.get("slug", ""),
            "title":         clean_text(item.get("title", "")),
            "image":         self._proxy(item.get("cover_url", "")),
            "author":        "",
            "latestChapter": f"Chapter {_num(latest)}" if latest else "",
            "status":        _status(item.get("status", "")),
            "updatedAt":     item.get("last_chapter_at", "") or "",
        }

    def _list(self, query: str, offset: int, limit: int) -> dict:
        data  = fetch_json(f"{BASE}/api/novels?{query}&limit={limit}&offset={offset}")
        items = data.get("items") or []
        total = int(data.get("total") or 0)
        return {
            "results": [self._card(i) for i in items if i.get("slug")],
            "hasMore": offset + len(items) < total,
        }

    # ── NovelProvider interface ───────────────────────────────────────────

    def hot(self) -> list:
        return cached(self._key("hot"), TTL_HOT,
                      lambda: self._list("sort=popular", 0, PAGE_SIZE)["results"])

    def latest(self, page: int = 1) -> dict:
        def run():
            out = self._list("sort=updated", (page - 1) * PAGE_SIZE, PAGE_SIZE)
            out["nextPage"] = page + 1
            return out
        return cached(self._key("latest", page), TTL_LATEST, run)

    def search(self, query, genre=None, status="All", page=1) -> dict:
        def run():
            q = f"sort=popular&q={quote(query)}"
            if genre:
                # The API's genre slugs are lower_snake ("slice_of_life"),
                # except Sci-Fi, which keeps its hyphen.
                slug = genre.strip().lower().replace(" ", "_")
                q += f"&genre={quote(slug)}"
            out = self._list(q, (page - 1) * SEARCH_SIZE, SEARCH_SIZE)
            if status in ("Ongoing", "Completed"):
                out["results"] = [r for r in out["results"] if r["status"] == status]
            out["nextPage"] = page + 1
            return out
        return cached(self._key("search", query, genre, status, page), TTL_SEARCH, run)

    def info(self, novel_id: str) -> dict:
        return cached(self._key("info", novel_id), TTL_INFO, lambda: self._info(novel_id))

    def chapter(self, chapter_id: str) -> dict:
        return cached(self._key("chapter", chapter_id), TTL_CHAP,
                      lambda: self._chapter(chapter_id))

    def fetch_image(self, url: str) -> tuple[bytes, str]:
        return fetch_bytes(url)

    # ── Detail + chapter list ─────────────────────────────────────────────

    def _info(self, slug: str) -> dict:
        d = fetch_json(f"{BASE}/api/novels/{quote(slug)}")

        chapters = []
        offset   = 0
        while True:
            page = fetch_json(f"{BASE}/api/novels/{quote(slug)}/chapters"
                              f"?order=asc&limit={CHAPTER_PAGE}&offset={offset}")
            items = page.get("items") or []
            for c in items:
                n = _num(c.get("number"))
                chapters.append({
                    "id":      f"{slug}/{n}",
                    "title":   _chapter_title(c.get("title", ""), n),
                    "chapter": n,
                })
            if len(items) < CHAPTER_PAGE:
                break
            offset += CHAPTER_PAGE

        desc  = (d.get("description") or "").replace("\r", "")
        paras = [clean_text(p) for p in re.split(r"\n\s*\n", desc)]
        return {
            "id":          slug,
            "title":       clean_text(d.get("title") or "Untitled"),
            "description": "\n\n".join(p for p in paras if p),
            "status":      _status(d.get("status", "")),
            "author":      ", ".join(a.get("name", "") for a in d.get("authors") or []
                                     if a.get("name")),
            "image":       self._proxy(d.get("cover_url", "")),
            "genres":      [g.get("name", "") for g in d.get("genres") or [] if g.get("name")],
            "chapters":    chapters,
        }

    # ── Chapter content ───────────────────────────────────────────────────
    # The body is plain text with one paragraph per line.

    def _chapter(self, chapter_id: str) -> dict:
        slug, _, number = chapter_id.rpartition("/")
        d = fetch_json(f"{BASE}/api/novels/{quote(slug)}/chapters/{quote(number)}/read")

        if d.get("locked"):
            paragraphs = [clean_text(d.get("lock_reason") or "")
                          or "This chapter is locked on Chikari."]
        else:
            paragraphs = [t for t in (clean_text(line) for line in
                                      (d.get("body") or "").split("\n")) if t]

        prev_n = d.get("prev_number")
        next_n = d.get("next_number")
        return {
            "id":         chapter_id,
            "title":      _chapter_title(d.get("title", ""), number),
            "paragraphs": paragraphs,
            "wordCount":  sum(len(p.split()) for p in paragraphs),
            "prevId":     f"{slug}/{_num(prev_n)}" if prev_n is not None else "",
            "nextId":     f"{slug}/{_num(next_n)}" if next_n is not None else "",
        }
