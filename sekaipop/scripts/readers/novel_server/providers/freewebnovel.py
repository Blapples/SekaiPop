# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
FreeWebNovel provider  –  https://freewebnovel.com

Implemented:
  - hot()      → /sort/most-popular
  - latest()   → /sort/latest-novel[/page]
  - info()     → /novel/<slug>
  - chapter()  → /novel/<slug>/<chapter-slug>
  - search()   → GET /search?keyword=<query>

"""

import json
import os
import random
import re
import threading
from urllib.parse import quote, urlparse

from .base import NovelProvider
from .utils import fetch, fetch_bytes, cached, cache_invalidate, clean_text, AJAX_HEADERS

BASE = "https://freewebnovel.com"

TTL_HOT    = 300
TTL_LATEST = 120
TTL_SEARCH = 600
TTL_INFO   = 1800
TTL_CHAP   = 86400

# Chapter lists are kept on disk between runs: fetching one is a paced request
# per 200 chapters (see utils.PAGE_INTERVAL), so a 3000-chapter novel takes
# ~15 s cold. With the list on disk, reopening it only fetches the pages that
# can hold new chapters.
CHAPTER_CACHE_DIR = os.path.expanduser("~/.cache/sekaipop/readers/novel-chapters")
_list_locks: dict = {}
_list_locks_lock  = threading.Lock()


def _list_lock(novel_id: str) -> threading.Lock:
    # One fetch per novel at a time: a second open of the same novel waits
    # for the first and reuses its result instead of doubling the requests.
    with _list_locks_lock:
        return _list_locks.setdefault(novel_id, threading.Lock())


def _list_path(novel_id: str) -> str:
    return os.path.join(CHAPTER_CACHE_DIR, novel_id.replace("/", "_") + ".json")


def _load_list(novel_id: str) -> list:
    try:
        with open(_list_path(novel_id)) as f:
            data = json.load(f)
        if not isinstance(data, list):
            return []
        # Lists saved before clean_text decoded every entity kept titles like
        # "Search &amp; Rescue"; cleaning already-clean text is a no-op.
        for c in data:
            if isinstance(c, dict) and isinstance(c.get("title"), str):
                c["title"] = clean_text(c["title"])
        return data
    except (OSError, ValueError):
        return []


def _save_list(novel_id: str, chapters: list):
    try:
        os.makedirs(CHAPTER_CACHE_DIR, exist_ok=True)
        tmp = _list_path(novel_id) + ".tmp"
        with open(tmp, "w") as f:
            json.dump(chapters, f)
        os.replace(tmp, _list_path(novel_id))
    except OSError as e:
        print(f"[freewebnovel] couldn't save chapter list for {novel_id}: {e}")


class FreeWebNovelProvider(NovelProvider):
    name  = "freewebnovel"
    label = "FreeWebNovel"

    # ── Internal helpers ──────────────────────────────────────────────────

    def _key(self, *parts) -> str:
        return f"{self.name}:" + ":".join(str(p) for p in parts)

    @staticmethod
    def _proxy(img_url: str, port: int = 5151) -> str:
        # Images can be relative (/files/...) or absolute
        full = img_url if img_url.startswith("http") else BASE + img_url
        return f"http://127.0.0.1:{port}/image?url={quote(full, safe='')}"

    # ── NovelProvider interface ───────────────────────────────────────────

    def search(self, query, genre=None, status="All", page=1) -> dict:
        key = self._key("search", query, genre, status, page)
        return cached(key, TTL_SEARCH, lambda: self._search(query, genre, status, page))

    def info(self, novel_id: str) -> dict:
        key  = self._key("info", novel_id)
        data = cached(key, TTL_INFO, lambda: self._info(novel_id))
        # A list cut short by the site isn't kept, so the next open resumes it.
        if data.get("partial"):
            cache_invalidate(key)
        return data

    def chapter(self, chapter_id: str) -> dict:
        return cached(self._key("chapter", chapter_id), TTL_CHAP, lambda: self._chapter(chapter_id))

    def hot(self) -> list:
        return cached(self._key("hot"), TTL_HOT, self._hot)

    def latest(self, page: int = 1) -> dict:
        return cached(self._key("latest", page), TTL_LATEST, lambda: self._latest(page))

    def fetch_image(self, url: str) -> tuple[bytes, str]:
        return fetch_bytes(url)

    # ── Shared list-card parser ───────────────────────────────────────────
    # Both hot() and latest() use the same .li-row card structure.

    def _parse_li_rows(self, html: str) -> list:
        results = []
        seen    = set()

        for block in re.finditer(
            r'<div class="li-row">([\s\S]*?)(?=<div class="li-row">|$)',
            html, re.S
        ):
            b = block.group(1)

            # Novel slug from href="/novel/some-slug" (no sub-path)
            slug_m = re.search(r'href="/novel/([^"/?]+)"', b)
            if not slug_m:
                continue
            slug = slug_m.group(1)
            if slug in seen:
                continue
            seen.add(slug)

            title_m = re.search(r'<h3 class="tit">\s*<a[^>]*>([^<]+)</a>', b)
            img_m   = re.search(r'<img\s+src="(/files/article/image/[^"]+)"', b)
            genres  = re.findall(r'href="/genre/[^"]*"[^>]*>([^<]+)</a>', b)
            chap_m  = re.search(r'<a[^>]+class="chapter"[^>]*title="([^"]*)"', b)

            results.append({
                "id":            f"novel/{slug}",
                "title":         clean_text(title_m.group(1)) if title_m else slug,
                "image":         self._proxy(img_m.group(1)) if img_m else "",
                "author":        "",
                "latestChapter": clean_text(chap_m.group(1)) if chap_m else "",
                "genres":        genres,
            })

        return results

    # ── Hot (weekly popular) ──────────────────────────────────────────────

    def _hot(self) -> list:
        # /most-popular/weekvisit is gone (404); the site now serves the
        # popular list under /sort/most-popular (same .li-row cards).
        html = fetch(f"{BASE}/sort/most-popular")
        return self._parse_li_rows(html)

    # ── Latest novels ─────────────────────────────────────────────────────

    def _latest(self, page: int) -> dict:
        url  = f"{BASE}/sort/latest-novel" if page == 1 else f"{BASE}/sort/latest-novel/{page}"
        html = fetch(url)

        results  = self._parse_li_rows(html)
        has_next = bool(
            re.search(r'<a[^>]+class="[^"]*next[^"]*"', html)
            or re.search(r'rel="next"', html)
            or re.search(r'href="[^"]*latest-novel/' + str(page + 1) + r'"', html)
        )

        return {"results": results, "hasMore": has_next, "nextPage": page + 1}

    # ── Novel info + full chapter list ────────────────────────────────────
    #
    # novel_id arrives as:  "novel/shadow-slave"
    # Page URL becomes:     https://freewebnovel.com/novel/shadow-slave
    #
    # Metadata lives in:    <div class="m-imgtxt">
    # Description lives in: <div class="inner"> inside <div class="m-desc">
    # Chapter list in:      <ul id="idData">

    # Parse <a href="/novel/<slug>/chapter-N" title="..." class="con"> anchors
    # out of a chunk of chapter-list HTML (inline list or ajax payload).
    # Note: the href slug is the canonical routable id; the visible title
    # number can drift from it (the site has duplicate/off-by-one titles),
    # so we trust the slug for the id and the title only for the label.
    def _parse_chapter_anchors(self, novel_id: str, html: str) -> list:
        out = []
        for m in re.finditer(
            r'<a\s+href="/novel/[^/]+/([^"]+)"\s+title="([^"]*)"[^>]*class="con"',
            html
        ):
            ch_slug  = m.group(1)          # e.g. "chapter-1"
            label    = clean_text(m.group(2))
            ch_num_m = re.search(r'[Cc]hapter[\s-]*([\d.]+)', label)
            out.append({
                # full routable id passed back to /chapter?id=
                "id":      f"{novel_id}/{ch_slug}",
                "title":   label,
                "chapter": ch_num_m.group(1) if ch_num_m else label,
            })
        return out

    # The whole list in one request: the endpoint behind the chapter <select>
    # in the reader (the approach LNReader's plugin uses). It takes the
    # novel's numeric article id from the novel page and answers with every
    # chapter as <option value="/novel/<slug>/chapter-N">CH.N: Title</option>
    # in a JSON {"html": …} envelope. `cid` is the chapter the reader is on;
    # any number within the list does. Returns None when the page doesn't
    # carry the ids or the reply isn't the expected shape, so the caller can
    # fall back to the paged walk.
    def _chapterlist_api(self, novel_id: str, html: str) -> list | None:
        aid_m   = re.search(r'data-article-id="(\d+)"', html) \
               or re.search(r'data-novel-id="(\d+)"', html) \
               or re.search(r'articleId:\s*(\d+)', html)
        total_m = re.search(r'data-total-chapters="(\d+)"', html)
        if not aid_m:
            return None
        total = int(total_m.group(1)) if total_m else 0
        slug  = novel_id.split("/")[-1]

        body = fetch(
            f"{BASE}/api/chapterlist.php",
            extra_headers={**AJAX_HEADERS, "Referer": f"{BASE}/{novel_id}"},
            form={"aid": aid_m.group(1), "acode": slug,
                  "cid": str(random.randrange(max(total, 1)))},
        )
        try:
            data = json.loads(body)
            if isinstance(data, dict):
                body = data.get("html", "")
        except ValueError:
            pass                 # a bare HTML fragment is fine too

        out = []
        for m in re.finditer(
            r'<option[^>]+value="/?novel/[^/"]+/([^"]+)"[^>]*>([\s\S]*?)</option>', body
        ):
            ch_slug  = m.group(1)
            # "CH.12: Title" → "Chapter 12: Title", matching the other lists
            label    = re.sub(r'^CH\.\s*', "Chapter ", clean_text(m.group(2)))
            num_m    = re.search(r'chapter-([\d.]+)', ch_slug) \
                    or re.search(r'[Cc]hapter[\s-]*([\d.]+)', label)
            out.append({
                "id":      f"{novel_id}/{ch_slug}",
                "title":   label,
                "chapter": num_m.group(1) if num_m else label,
            })

        if not out or (total and len(out) < total * 0.9):
            print(f"[freewebnovel] chapterlist.php gave {len(out)}/{total} "
                  f"for {novel_id}; falling back to paging")
            return None
        return out

    # One page of the ajax chapter endpoint → (chapters, page_info). The page
    # size is capped server-side (200 as of 2026-09; the web page itself asks
    # for 40) whatever pageSize we send; the reply says what it used.
    def _ajax_page(self, novel_id: str, page: int) -> tuple[list, dict]:
        url  = f"{BASE}/{novel_id}?ajax=chapters&page={page}&pageSize=200"
        data = json.loads(fetch(url, extra_headers=AJAX_HEADERS))
        if not isinstance(data, dict) or data.get("code", 200) != 200:
            raise ValueError(f"unexpected chapter-list reply for page {page}")
        return self._parse_chapter_anchors(novel_id, data.get("html", "")), data

    # The full chapter list, oldest first → (chapters, partial).
    #
    # chapterlist.php first (one request). If that's unavailable: page 1
    # always comes fresh: it carries totalChapters/totalPage, so it
    # tells us whether the list on disk is complete. Pages are walked in
    # order from the first one the saved list doesn't fully cover, so what's
    # saved is always an unbroken run from chapter 1. If the site still
    # refuses a page after utils.fetch's retries, the walk stops and what we
    # have is returned as a partial list (saved, so the next open resumes).
    def _fetch_chapter_list(self, novel_id: str, inline: list,
                            html: str = "") -> tuple[list, bool]:
        with _list_lock(novel_id):
            # One request for the whole list when the site allows it…
            try:
                full = self._chapterlist_api(novel_id, html)
            except Exception as e:
                print(f"[freewebnovel] chapterlist.php failed for {novel_id}: {e}")
                full = None
            if full:
                chapters = self._dedupe_sort_chapters(full + inline)
                _save_list(novel_id, chapters)
                return chapters, False

            # …else page through the ajax listing, resuming from disk.
            known = _load_list(novel_id)
            first, meta = self._ajax_page(novel_id, 1)

            page_size  = int(meta.get("pageSize") or 200)
            total_page = int(meta.get("totalPage") or 1)
            total      = int(meta.get("totalChapters") or 0)

            chapters = self._dedupe_sort_chapters(known + inline + first)
            if total and len(chapters) >= total:
                if len(known) < len(chapters):
                    _save_list(novel_id, chapters)
                return chapters, False

            partial = False
            start   = max(2, len(chapters) // page_size + 1)
            for page in range(start, min(total_page, 200) + 1):
                try:
                    more, _ = self._ajax_page(novel_id, page)
                except Exception as e:
                    print(f"[freewebnovel] chapter list for {novel_id} stopped at "
                          f"page {page}/{total_page}: {e}")
                    partial = True
                    break
                chapters.extend(more)

            chapters = self._dedupe_sort_chapters(chapters)
            _save_list(novel_id, chapters)
            return chapters, partial

    # Merge chapter records, dropping duplicate slugs and ordering by the
    # numeric part of the routable slug (falling back to discovery order).
    @staticmethod
    def _dedupe_sort_chapters(chapters: list) -> list:
        seen, deduped = set(), []
        for c in chapters:
            if c["id"] in seen:
                continue
            seen.add(c["id"])
            deduped.append(c)

        def _key(item):
            m = re.search(r'chapter[\s-]*([\d.]+)', item["id"], re.I)
            return float(m.group(1)) if m else float("inf")

        return sorted(deduped, key=_key)

    def _info(self, novel_id: str) -> dict:
        url  = f"{BASE}/{novel_id}"
        html = fetch(url)

        # Cover — <meta name="image"> is more reliable than og:image on this site
        cover_m = re.search(r'<meta name="image" content="([^"]+)"', html)
        if not cover_m:
            cover_m = re.search(r'<meta property="og:image" content="([^"]+)"', html)

        # Title
        title_m = re.search(r'<meta property="og:title" content="([^"]+)"', html)

        # Author: <a href="/author/Guiltythree" class="a1" title="Guiltythree">
        author_m = re.search(r'<a href="/author/[^"]*"[^>]*title="([^"]*)"', html)

        # Status: <span class="s1 s2"><a ...>OnGoing</a></span>
        status_m = re.search(
            r'<span class="s1 s2">\s*<a[^>]*>([^<]+)</a>\s*</span>', html
        )

        # Genres — grab only from the .m-imgtxt block to avoid nav links
        genres = []
        imgtxt_m = re.search(r'<div class="m-imgtxt">([\s\S]*?)</div>\s*</div>', html)
        if imgtxt_m:
            genres = [clean_text(g) for g in re.findall(
                r'<a href="/genre/[^"]*"[^>]*title="[^"]*">([^<]+)</a>',
                imgtxt_m.group(1)
            )]

        # Description — <div class="inner"> … <p>…</p> … </div>
        description = ""
        desc_m = re.search(
            r'<div class="inner">([\s\S]*?)</div>\s*</div>\s*<div class="showheight"',
            html
        )
        if desc_m:
            paras = re.findall(r'<p[^>]*>([\s\S]*?)</p>', desc_m.group(1))
            description = "\n\n".join(clean_text(p) for p in paras if clean_text(p))

        # Chapter list.
        # The novel page only embeds the first 40 chapters in
        # <ul id="idData">; the rest come from chapterlist.php or, failing
        # that, the paginated ajax endpoint (see _fetch_chapter_list).
        inline = []
        chlist_m = re.search(r'<ul[^>]+id="idData"[^>]*>([\s\S]*?)</ul>', html)
        if chlist_m:
            inline = self._parse_chapter_anchors(novel_id, chlist_m.group(1))

        try:
            chapters, partial = self._fetch_chapter_list(novel_id, inline, html)
        except Exception as e:
            # Even page 1 failed: show what the novel page itself listed
            # (plus anything saved) rather than failing the whole detail view.
            print(f"[freewebnovel] chapter list for {novel_id} unavailable: {e}")
            chapters = self._dedupe_sort_chapters(_load_list(novel_id) + inline)
            partial  = True

        raw_cover = cover_m.group(1) if cover_m else ""
        return {
            "id":          novel_id,
            "title":       clean_text(title_m.group(1)) if title_m else "",
            "description": description,
            "status":      clean_text(status_m.group(1)) if status_m else "",
            "author":      clean_text(author_m.group(1)) if author_m else "",
            "image":       self._proxy(raw_cover) if raw_cover else "",
            "genres":      genres,
            "chapters":    chapters,   # oldest-first, as returned by the page
            "partial":     partial,    # the site cut the list short
        }

    # ── Chapter content ───────────────────────────────────────────────────
    #
    # chapter_id arrives as:  "novel/shadow-slave/chapter-1"
    # Page URL becomes:       https://freewebnovel.com/novel/shadow-slave/chapter-1
    #
    # Title:    <span class="chapter">Chapter 1 Nightmare Begins</span>
    # Content:  <div id="article"> … <p>…</p> … </div>
    #           Ad divs appear inline inside #article — skip any <p> that
    #           contains a nested <script> or <div>.
    # Prev:     <a href="…" id="prev_url">  (bottom nav, most reliable)
    # Next:     <a href="…" id="next_url">

    def _chapter(self, chapter_id: str) -> dict:
        url  = f"{BASE}/{chapter_id}"
        html = fetch(url)

        # Title — the <span class="chapter"> inside .top is the canonical source
        title_m = re.search(r'<span class="chapter">([^<]+)</span>', html)
        if not title_m:
            title_m = re.search(r'<meta property="og:title" content="([^"]+)"', html)

        # Content — everything inside <div id="article">…</div>
        # The closing marker <!--bg--> comes right after </div> so we use it
        # as a reliable end anchor instead of trying to match nested divs.
        paragraphs = []
        article_m  = re.search(
            r'<div[^>]+id="article"[^>]*>([\s\S]*?)<!--bg-->', html
        )
        if not article_m:
            # Fallback: grab up to 100 000 chars after the opening tag
            article_m = re.search(
                r'<div[^>]+id="article"[^>]*>([\s\S]{0,100000})', html
            )

        if article_m:
            content = article_m.group(1)
            for raw in re.findall(r'<p[^>]*>([\s\S]*?)</p>', content):
                # Ad blocks embed <script> or <div> inside <p> — skip them
                if '<script' in raw or '<div' in raw:
                    continue
                t = clean_text(raw)
                if t:
                    paragraphs.append(t)

        # Prev / Next — use id="prev_url" / id="next_url" on the bottom nav
        def _path(pattern: str) -> str:
            m = re.search(pattern, html)
            if not m:
                return ""
            return urlparse(m.group(1)).path.strip("/")

        prev_raw = _path(r'<a[^>]+id="prev_url"[^>]+href="([^"]+)"')
        next_raw = _path(r'<a[^>]+id="next_url"[^>]+href="([^"]+)"')

        # If prev/next href points at the novel page (2 segments) not a chapter
        # (3 segments: novel/slug/chapter-N), treat as absent.
        def _is_chapter(path: str) -> bool:
            return len(path.split("/")) >= 3

        return {
            "id":         chapter_id,
            "title":      clean_text(title_m.group(1)).strip() if title_m else "",
            "paragraphs": paragraphs,
            "wordCount":  sum(len(p.split()) for p in paragraphs),
            "prevId":     prev_raw if _is_chapter(prev_raw) else "",
            "nextId":     next_raw if _is_chapter(next_raw) else "",
        }

    # ── Search ────────────────────────────────────────────────────────────

    def _search(self, query, genre, status, page) -> dict:
        # FWN search is now a GET: /search?keyword=<query>.
        # (A POST to /search just 303-redirects here, and the old
        # "searchkey" field name no longer matches anything.)
        url  = f"{BASE}/search?keyword={quote(query)}"
        html = fetch(url, extra_headers={"Referer": BASE + "/"})

        results = self._parse_li_rows(html)
        return {
            "results":  results,
            "hasMore":  False,   # FWN search is single-page
            "nextPage": 1,
        }