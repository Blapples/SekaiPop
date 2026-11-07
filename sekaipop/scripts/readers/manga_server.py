#!/usr/bin/env python3
# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
Manga backend server for QuickShell ServiceManga.
Search, filters and metadata come from AniList; chapters and pages come from
WeebCentral. Serves clean JSON on http://127.0.0.1:5150

Endpoints:
  GET /al/browse?q=&genres=a,b&tags=a|b&format=&country=&status=a,b&year=&score_min=&score_max=&sort=&adult=0&page=1
                 (tags are split on "|"; score_min / score_max are AniList's 0-100 average score)
  GET /al/tags                    (AniList's tag list: [{name, category, isAdult}], for the tag filter)
  GET /al/info?id=<anilist_id>    (AniList details + the matched WeebCentral chapters)
  GET /al/candidates?anilistId=<n>&q=<text>   (WeebCentral series to pick a match from)
  POST /al/match/set    {anilistId, id, title}
  POST /al/match/clear  {anilistId}
  GET  /al/auth/status            (is someone logged in to AniList, and who; never the token)
  POST /al/auth/client  {clientId}            (the AniList app's client ID, once)
  POST /al/auth/start                         (begins a login: {url, nonce, redirectUri})
  GET  /al/auth/callback                      (the page AniList sends the browser back to)
  POST /al/auth/token   {token, nonce}        (the callback page, or a pasted token, hands it in)
  POST /al/auth/logout
  GET  /al/track?id=<anilistId>               (the logged-in user's list entry for a title: status, progress)
  POST /al/track/progress {anilistId, progress, volumes}   (what has been read; only ever goes up)
  POST /al/track/set {anilistId, status, progress, volumes}  (set by hand; may lower)
  GET  /al/list?status=CURRENT&q=&format=&country=&genres=a,b&tags=a|b&year=&mstatus=a,b&sort=SCORE
                 (the logged-in user's own list, one status at a time, filtered and sorted, with the
                  size of every status for the tabs: {status, counts, total, scoreFormat, entries})
  GET /search?q=<query>&type=<Manga|Manhwa|Manhua>&offset=<n>   (WeebCentral's own search)
  GET /info?id=<series_id>        (id = "SERIESID/Slug-Name")
  GET /pages?chapterId=<id>
  GET /image?url=<encoded_url>    (image proxy — bypasses CDN UA checks)
  GET /hot
  GET /latest?page=<n>
  GET /browse?sort=popular|latest|rating|views&page=<n>
                 (the picked source's OWN catalog, Mihon-style: Popular and Latest are the source's two
                  feeds; rating / views only where the source can sort that way. No AniList involved.
                  Answers {results, hasMore, nextPage, sorts}; sorts = what this source offers)
  GET /provider                   (which site the chapters come from: weebcentral, mangadex or suwayomi)
  POST /provider {provider}       (switch it; kept in provider.json)
  GET /mdpage?c=<chapter id>&i=<n>   (one MangaDex page; asks for a fresh image server when needed)
  GET /swpage?c=<chapter id>&i=<n>   (one page of a chapter read through Suwayomi)
  GET /sw/status                  (is Suwayomi set up / running; are the sources picked by hand)
  GET /sw/extensions?refresh=1    (Suwayomi's extensions; refresh=1 asks the repositories again)
  POST /sw/ext {action, pkg}      (install / update / uninstall one extension; action "update-all")
  GET /sw/repos, POST /sw/repos {add | remove | repos}   (the extension repositories)
  GET /sw/sources, POST /sw/sources {id, use | auto | focus}   (which sources Browse and Latest ask;
                                  focus = one picked source's id to ask only it, "" for all of them)
  GET /health
"""

import os
import sys
import atexit
import signal
import subprocess
import re
import random
import json
import time
import base64
import hmac
import secrets
import html as _html
import shutil
import difflib
import threading
import unicodedata
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs, quote, unquote, urlencode
from concurrent.futures import ThreadPoolExecutor

# ── Use curl_cffi for browser-grade TLS fingerprinting (bypasses Cloudflare)
# Install: pip install curl_cffi --user
try:
    from curl_cffi.requests import Session as CffiSession
    _USE_CFFI = True
    print("[manga-server] Using curl_cffi (Firefox impersonation)")
except ImportError:
    import requests as _requests_mod
    _USE_CFFI = False
    print("[manga-server] curl_cffi not found, falling back to requests (may timeout on Cloudflare)")

PORT        = 5150
BASE        = "https://weebcentral.com"
COVER_SMALL = "https://temp.compsci88.com/cover/small"
COVER_BASE  = "https://temp.compsci88.com/cover/fallback"
PAGE_LIMIT  = 32
# WeebCentral links are root-relative now ("/series/…"); older markup was absolute
HREF        = r'href="(?:https://weebcentral\.com)?'

# ── Persistent storage ─────────────────────────────────────────────────────
DATA_DIR       = os.path.expanduser("~/.local/share/sekaipop/readers/manga")
FAVORITES_FILE = os.path.join(DATA_DIR, "favorites.json")
DOWNLOADS_DIR  = os.path.join(DATA_DIR, "downloads")
os.makedirs(DATA_DIR,      exist_ok=True)
os.makedirs(DOWNLOADS_DIR, exist_ok=True)

HEADERS = {
    "User-Agent":                "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "Accept":                    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language":           "en-US,en;q=0.5",
    "Accept-Encoding":           "gzip, deflate, br",
    "Connection":                "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest":            "document",
    "Sec-Fetch-Mode":            "navigate",
    "Sec-Fetch-Site":            "none",
    "Sec-Fetch-User":            "?1",
    "DNT":                       "1",
}
SEARCH_HEADERS = {
    **HEADERS,
    "HX-Request":        "true",
    "HX-Target":         "search-results",
    "Sec-Fetch-Dest":    "empty",
    "Sec-Fetch-Mode":    "cors",
    "Sec-Fetch-Site":    "same-origin",
    "X-Requested-With":  "XMLHttpRequest",
}

# One session per thread: the server and _info() fetch concurrently, and a
# shared curl handle intermittently fails the TLS handshake.
_tls = threading.local()


def _session():
    sess = getattr(_tls, "session", None)
    if sess is None:
        if _USE_CFFI:
            sess = CffiSession(impersonate="firefox")
        else:
            sess = _requests_mod.Session()
            sess.headers.update(HEADERS)
        _tls.session = sess
    return sess


def _get(url, headers, timeout):
    """GET with one retry on connection-level errors (TLS resets, timeouts)."""
    try:
        return _session().get(url, headers=headers, timeout=timeout)
    except Exception as e:
        if getattr(e, "response", None) is not None:
            raise
        _tls.session = None
        return _session().get(url, headers=headers, timeout=timeout)


def _post_json(url, payload, headers, timeout):
    """POST JSON with one retry on connection-level errors; returns the response."""
    try:
        return _session().post(url, json=payload, headers=headers, timeout=timeout)
    except Exception as e:
        if getattr(e, "response", None) is not None:
            raise
        _tls.session = None
        return _session().post(url, json=payload, headers=headers, timeout=timeout)


# ── TTL Cache ──────────────────────────────────────────────────────────────

_cache      = {}
_cache_lock = threading.Lock()

TTL_HOT    = 300
TTL_LATEST = 120
TTL_SEARCH = 600
TTL_INFO   = 1800
TTL_PAGES  = 3600


def _cached(key, ttl, fn):
    with _cache_lock:
        entry = _cache.get(key)
    if entry:
        val, expires = entry
        if time.monotonic() < expires:
            return val
    val = fn()
    with _cache_lock:
        _cache[key] = (val, time.monotonic() + ttl)
    return val


def _cache_drop(prefix):
    """Forget every cached answer whose key starts with `prefix`."""
    with _cache_lock:
        for k in [k for k in _cache if k.startswith(prefix)]:
            _cache.pop(k, None)


# ── Helpers ────────────────────────────────────────────────────────────────

def fetch(url, extra_headers=None, timeout=30):
    headers = {**HEADERS, **(extra_headers or {})}
    r = _get(url, headers, timeout)
    r.raise_for_status()
    return r.text


def _raw_get(url, timeout=30):
    """Return raw bytes + content-type for image proxy."""
    r = _get(url, HEADERS, timeout)
    if r.status_code in (429, 500, 502, 503, 504):
        # A CDN that is throttling or briefly down: one more try before the cover
        # reaches the panel as a failed image.
        time.sleep(0.6)
        r = _get(url, HEADERS, timeout)
    r.raise_for_status()
    return r.content, r.headers.get("Content-Type", "image/jpeg")


def series_id(full_id):
    return full_id.split("/")[0]


def clean_text(html):
    # WeebCentral sends "Wasn&#x27;t": decode it, or titles with an apostrophe or
    # an ampersand never compare equal to AniList's.
    return _html.unescape(re.sub(r"<[^>]+>", "", html)).strip()


def proxy_url(img_url):
    return f"http://127.0.0.1:{PORT}/image?url={quote(img_url, safe='')}"


def cover_url(sid):
    return proxy_url(f"{COVER_SMALL}/{sid}.webp")


# ── Search ─────────────────────────────────────────────────────────────────

def search(query, mtype=None, offset=0, sort="Latest Updates"):
    key = f"search:{query}:{mtype}:{offset}:{sort}"
    with _cache_lock:
        entry = _cache.get(key)
    if entry and time.monotonic() < entry[1]:
        return entry[0]
    val = _search(query, mtype, offset, sort)
    # An empty answer is not kept: it is often a hiccup, and it would hide the
    # title for the next ten minutes.
    if val.get("results"):
        with _cache_lock:
            _cache[key] = (val, time.monotonic() + TTL_SEARCH)
    return val


def _search(query, mtype, offset, sort):
    params = (
        f"text={quote(query)}"
        f"&limit={PAGE_LIMIT}"
        f"&offset={offset}"
        f"&official=Any&anime_only=any&display_mode=Minimal+Display"
        f"&sort={quote(sort)}"
    )
    if mtype:
        params += f"&included_type={quote(mtype)}"

    html     = fetch(f"{BASE}/search/data?{params}", extra_headers=SEARCH_HEADERS)
    articles = re.findall(r"<article[^>]*>(.*?)</article>", html, re.S)

    results = []
    for a in articles:
        href  = re.search(HREF + r'/series/([^"]+)"', a)
        title = re.search(r"<h2[^>]*>([^<]+)</h2>", a)
        if not (href and title):
            continue
        sid  = href.group(1)
        bid  = series_id(sid)
        divs = re.findall(r"<div>([^<]+)</div>", a)
        tags = re.findall(r"<span>([^<,]+),?</span>", a)
        results.append({
            "id":     sid,
            "title":  clean_text(title.group(1)),
            "image":  cover_url(bid),
            "status": divs[2].strip() if len(divs) >= 3 else "",
            "year":   divs[1].strip() if len(divs) >= 2 else "",
            "type":   divs[0].strip() if len(divs) >= 1 else "",
            "tags":   [t.strip() for t in tags if t.strip()],
        })

    return {
        "results":    results,
        "hasMore":    len(results) >= PAGE_LIMIT,
        "nextOffset": offset + len(results),
    }


# ── Chapter / volume labels ────────────────────────────────────────────────
# Some WeebCentral series are listed by volume ("Volume 3"), not by chapter,
# and a few mix both or add extras ("Side Story 2", "Oneshot"). Every label is
# split into a kind and a number so the rest of the server (and the panel) never
# has to guess what "chapter" holds.

_NUM_RE = re.compile(r"\d+(?:\.\d+)?")


def parse_label(label):
    """'Volume 3' -> ('volume', '3'); 'Chapter 12.5' -> ('chapter', '12.5');
    'Side Story 2' -> ('extra', '2'); 'Oneshot' -> ('extra', 'Oneshot')."""
    text = (label or "").strip()
    low  = text.lower()
    m    = _NUM_RE.search(text)
    num  = m.group(0) if m else ""
    if re.match(r"(?:volume|vol)\b", low):
        return "volume", num or text
    if re.match(r"(?:chapter|ch|episode|ep)\b", low) or (num and re.fullmatch(r"[\d.\s]+", text)):
        return "chapter", num or text
    if not text:
        return "chapter", ""
    return "extra", num or text


def chapter_sort_num(value):
    """A chapter number as a float for sorting; anything that is not a number sorts as 0."""
    try:
        return float(value)
    except (TypeError, ValueError):
        m = _NUM_RE.search(str(value or ""))
        return float(m.group(0)) if m else 0.0


# ── Info + Chapters ─────────────────────────────────────────────────────────

def info(full_id):
    return _cached(f"info:{full_id}", TTL_INFO, lambda: _info(full_id))


def _info(full_id):
    if is_md(full_id):
        return md_info(full_id)
    if is_sw(full_id):
        return sw_info(full_id)
    bid = series_id(full_id)

    with ThreadPoolExecutor(max_workers=2) as ex:
        f_detail = ex.submit(fetch, f"{BASE}/series/{full_id}")
        f_chaps  = ex.submit(fetch, f"{BASE}/series/{bid}/full-chapter-list")
        detail_html = f_detail.result()
        ch_html     = f_chaps.result()

    title_m  = re.search(r"<title>([^|<]+)", detail_html)
    status_m = re.search(r"Status: </strong>.*?<a[^>]+>([^<]+)</a>", detail_html, re.S)
    og_img   = re.search(r'og:image" content="([^"]+)"', detail_html)

    authors = []
    for block in re.findall(r'(?:Author|Artist)(?:s|\(s\))?: </strong>(.*?)(?:</li>|</ul>)', detail_html, re.S):
        for name in re.findall(r"<a[^>]+>([^<]+)</a>", block):
            n = name.strip()
            if n and n not in authors:
                authors.append(n)

    description = ""
    for p in re.findall(r"<p[^>]*>([\s\S]{80,600}?)</p>", detail_html):
        c = clean_text(p)
        if c and "{" not in c and "function" not in c and "Login" not in c:
            description = c
            break

    anchors = re.findall(
        r'<a\b[^>]*?\bhref="(?:https://weebcentral\.com)?/chapters/([^"]+)"[^>]*>([\s\S]*?)</a>',
        ch_html, re.S
    )
    chapters = []
    for cid, inner in anchors:
        spans      = re.findall(r"<span[^>]*>([\s\S]*?)</span>", inner)
        text_spans = [clean_text(s) for s in spans if clean_text(s) and "{" not in s and len(clean_text(s)) > 1]
        ch_label   = text_spans[0] if text_spans else ""
        if not ch_label:                       # unusual markup: fall back to the link's own text
            ch_label = re.sub(r"\s+", " ", clean_text(re.sub(r"<time[\s\S]*?</time>", "", inner))).strip()
            if "{" in ch_label:
                ch_label = ""
        kind, ch_num = parse_label(ch_label)
        dt_m       = re.search(r'datetime="([^"]+)"', inner)
        chapters.append({
            "id":        cid,
            "title":     ch_label,
            "chapter":   ch_num,
            "kind":      kind,
            "publishAt": dt_m.group(1) if dt_m else "",
        })
    chapters.reverse()
    for i, c in enumerate(chapters):          # site order, oldest first
        c["index"] = i

    raw_cover = og_img.group(1) if og_img else f"{COVER_BASE}/{bid}.jpg"
    return {
        "id":          full_id,
        "title":       clean_text(title_m.group(1)).strip() if title_m else "",
        "description": description,
        "status":      status_m.group(1).strip() if status_m else "",
        "image":       proxy_url(raw_cover),
        "authors":     authors,
        "chapters":    chapters,
    }


# ── Latest Updates ─────────────────────────────────────────────────────────

def latest_updates(page=1):
    return _cached(f"latest:{page}", TTL_LATEST, lambda: _latest_updates(page))


def _latest_updates(page):
    html     = fetch(f"{BASE}/latest-updates/{page}")
    articles = re.findall(r"<article([^>]*)>([\s\S]*?)</article>", html, re.S)
    results  = []

    for attrs, body in articles:
        title_m = re.search(r'data-tip="([^"]+)"', attrs)
        series  = re.search(HREF + r'/series/([A-Z0-9]+)/([^"]+)"', body)
        cover   = re.search(r'<img src="(https://temp\.compsci88\.com/[^"]+)"', body)
        ch_num  = re.search(r"(?:Chapter|Episode|Volume|Vol\.?) ?([0-9][^<]*)<", body)
        dt      = re.search(r'datetime="([^"]+)"', body)

        if not (series and title_m):
            continue

        sid = series.group(1)
        results.append({
            "id":        f"{sid}/{series.group(2)}",
            "title":     _html.unescape(title_m.group(1)),
            "image":     proxy_url(cover.group(1)) if cover else cover_url(sid),
            "status":    "",
            "type":      "",
            "chapter":   ch_num.group(1).strip() if ch_num else "",
            "updatedAt": dt.group(1) if dt else "",
        })

    has_more = bool(re.search(
        rf'hx-get="(?:https://weebcentral\.com)?/latest-updates/{page + 1}"', html
    ))

    return {
        "results":  results,
        "hasMore":  has_more,
        "nextPage": page + 1,
    }


# ── Hot Updates ────────────────────────────────────────────────────────────

def hot_updates():
    return _cached("hot", TTL_HOT, _hot_updates)


def _hot_updates():
    html     = fetch(f"{BASE}/hot-updates")
    articles = re.findall(r"<article[^>]*>([\s\S]*?)</article>", html, re.S)
    results  = []
    seen     = set()

    for a in articles:
        series  = re.search(HREF + r'/series/([A-Z0-9]+)/([^"]+)"', a)
        chapter = re.search(HREF + r'/chapters/([A-Z0-9]+)"', a)
        cover   = re.search(r'<img src="(https://temp\.compsci88\.com/[^"]+)"', a)
        title   = re.search(r'alt="([^"]+) cover"', a)
        ch_num  = re.search(r"(?:Chapter|Episode|Volume|Vol\.?) ?([0-9][^<]*)</", a)
        dt      = re.search(r'datetime="([^"]+)"', a)

        if not (series and chapter and title):
            continue
        sid = series.group(1)
        if sid in seen:
            continue
        seen.add(sid)

        results.append({
            "id":        f"{sid}/{series.group(2)}",
            "title":     _html.unescape(title.group(1)),
            "image":     proxy_url(cover.group(1)) if cover else cover_url(sid),
            "status":    "",
            "type":      "",
            "chapter":   ch_num.group(1) if ch_num else "",
            "updatedAt": dt.group(1) if dt else "",
        })

    return results


# ── Pages ──────────────────────────────────────────────────────────────────

def pages(chapter_id):
    return _cached(f"pages:{chapter_id}", TTL_PAGES, lambda: _pages(chapter_id))


def _pages(chapter_id):
    if is_md(chapter_id):
        return md_pages(chapter_id)
    if is_sw(chapter_id):
        return sw_pages(chapter_id)
    url  = f"{BASE}/chapters/{chapter_id}/images?is_prev=False&current_page=1&reading_style=long_strip"
    html = fetch(url)

    imgs = re.findall(r'<img[^>]+class="[^"]*maw-w-full[^"]*"[^>]+src="([^"]+)"', html)
    if not imgs:
        imgs = re.findall(r'<img[^>]+src="(https://[^"]+\.(?:jpg|jpeg|png|webp)[^"]*?)"', html, re.I)
        imgs = [i for i in imgs if "weebcentral.com" not in i and "logo" not in i.lower()]

    return [{"page": i + 1, "img": proxy_url(img)} for i, img in enumerate(imgs)]


# ── AniList: search, filters, metadata ─────────────────────────────────────
# AniList answers "what is there and what is it like" (the same search and
# filters Seanime's manga page uses); WeebCentral answers "where do I read it".
# A title is matched to its WeebCentral series by name the first time it is
# opened, and the match is kept in anilist_matches.json (and can be changed).

ANILIST_URL = "https://graphql.anilist.co"
AL_PER_PAGE = 32
TTL_AL      = 600
TTL_AL_INFO = 1800
MATCH_FILE  = os.path.join(DATA_DIR, "anilist_matches.json")
MATCH_MIN   = 0.88      # below this a title is not matched on its own: you pick

AL_SORTS     = {"TRENDING_DESC", "POPULARITY_DESC", "SCORE_DESC", "FAVOURITES_DESC",
                "START_DATE_DESC", "UPDATED_AT_DESC", "SEARCH_MATCH"}
AL_FORMATS   = {"MANGA", "ONE_SHOT"}          # novels have their own reader
AL_STATUSES  = {"RELEASING", "FINISHED", "NOT_YET_RELEASED", "CANCELLED", "HIATUS"}
AL_COUNTRIES = {"JP", "KR", "CN", "TW"}
TTL_AL_TAGS  = 7 * 86400        # the tag list changes about never
TAGS_FILE    = os.path.join(DATA_DIR, "al_tags.json")
AL_TAG_MAX   = 12               # tags in one search, so a URL stays sane
AL_GENRES    = {"Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror",
                "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance",
                "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"}

_AL_STATUS_LABEL = {
    "RELEASING": "Releasing", "FINISHED": "Finished", "NOT_YET_RELEASED": "Upcoming",
    "CANCELLED": "Cancelled", "HIATUS": "Hiatus",
}
# Country of origin -> the label on the cards, and WeebCentral's own type word
_AL_TYPE_LABEL = {"JP": "MANGA", "KR": "MANHWA", "CN": "MANHUA", "TW": "MANHUA"}
_WC_TYPE       = {"JP": "Manga", "KR": "Manhwa", "CN": "Manhua", "TW": "Manhua"}

_AL_CARD = """id title{romaji english native} coverImage{large extraLarge} format status
  startDate{year} averageScore genres countryOfOrigin"""

_AL_BROWSE_Q = """
query ($page:Int,$perPage:Int,$search:String,$sort:[MediaSort],$genre_in:[String],
       $tag_in:[String],$format_in:[MediaFormat],$status_in:[MediaStatus],
       $country:CountryCode,$sd_gt:FuzzyDateInt,$sd_lt:FuzzyDateInt,
       $score_gt:Int,$score_lt:Int,$adult:Boolean) {
  Page(page:$page, perPage:$perPage) {
    pageInfo { hasNextPage currentPage }
    media(type:MANGA, search:$search, sort:$sort, genre_in:$genre_in, tag_in:$tag_in,
          format_in:$format_in, status_in:$status_in, countryOfOrigin:$country,
          startDate_greater:$sd_gt, startDate_lesser:$sd_lt,
          averageScore_greater:$score_gt, averageScore_lesser:$score_lt, isAdult:$adult) {
      %s
    }
  }
}
""" % _AL_CARD

_AL_TAGS_Q = """
query { MediaTagCollection { name category isAdult isGeneralSpoiler } }
"""

_AL_MEDIA_Q = """
query ($id:Int) {
  Media(id:$id, type:MANGA) {
    %s synonyms description(asHtml:false) bannerImage chapters volumes siteUrl
    startDate{year month day} endDate{year month day}
    isLicensed meanScore popularity favourites
    externalLinks { site url type language }
    tags { name rank isMediaSpoiler category }
    staff(perPage:10, sort:RELEVANCE) { edges { role node { name { full } } } }
  }
}
""" % _AL_CARD


class AniListAuthError(RuntimeError):
    """AniList did not accept the login token (it ran out, or it was revoked)."""


def _al_request(query, variables, token=None):
    headers = {
        "Content-Type":    "application/json",
        "Accept":          "application/json",
        "Accept-Encoding": "gzip, deflate",
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    r = _post_json(ANILIST_URL, {"query": query, "variables": variables}, headers, 20)
    if r.status_code == 429:               # AniList's per-minute limit: wait it out once
        try:
            wait = min(int(r.headers.get("Retry-After", "2")), 8)
        except ValueError:
            wait = 2
        time.sleep(wait)
        r = _post_json(ANILIST_URL, {"query": query, "variables": variables}, headers, 20)
        if r.status_code == 429:
            raise RuntimeError("AniList is rate limiting, try again in a moment")
    try:
        data = r.json()
    except ValueError:
        r.raise_for_status()
        raise RuntimeError("AniList sent an unreadable reply")
    if token and (r.status_code == 401 or any(
            "invalid token" in str(e.get("message", "")).lower() for e in data.get("errors") or [])):
        auth_forget(token)                 # revoked or run out: stop offering a login that is dead
        raise AniListAuthError("Your AniList login has run out. Log in again.")
    if data.get("errors"):
        raise RuntimeError("AniList: " + "; ".join(str(e.get("message")) for e in data["errors"]))
    r.raise_for_status()
    return data["data"]


def _al_title(m):
    t = m.get("title") or {}
    return t.get("english") or t.get("romaji") or t.get("native") or "?"


def _al_cover(m):
    c = m.get("coverImage") or {}
    return c.get("extraLarge") or c.get("large") or ""


def _al_card(m):
    year = (m.get("startDate") or {}).get("year") or 0
    fmt  = m.get("format") or ""
    return {
        "id":        f"al:{m['id']}",
        "anilistId": m["id"],
        "title":     _al_title(m),
        "image":     proxy_url(_al_cover(m)) if _al_cover(m) else "",
        "type":      "ONE-SHOT" if fmt == "ONE_SHOT" else _AL_TYPE_LABEL.get(m.get("countryOfOrigin"), "MANGA"),
        "status":    _AL_STATUS_LABEL.get(m.get("status"), ""),
        "year":      year,
        "score":     m.get("averageScore") or 0,
        "genres":    m.get("genres") or [],
    }


def _al_score(v):
    """A 0-100 score from the panel, or 0 for none."""
    try:
        v = int(v)
    except (TypeError, ValueError):
        return 0
    return v if 1 <= v <= 100 else 0


def al_browse(q="", genres=(), fmt="", country="", status=(), year=0,
              sort="", adult=False, page=1, tags=(), score_min=0, score_max=0):
    q      = (q or "").strip()
    genres = tuple(g for g in genres if g in AL_GENRES)
    # `status` is one name or several (the panel picks any number); empty = any
    if isinstance(status, str):
        status = [x for x in status.split(",") if x]
    status = tuple(sorted({x for x in status if x in AL_STATUSES}))
    fmt    = fmt     if fmt     in AL_FORMATS   else ""
    country = country if country in AL_COUNTRIES else ""
    year   = year if 1900 <= year <= 2100 else 0
    tags   = _al_clean_tags(tags)
    score_min, score_max = _al_score(score_min), _al_score(score_max)
    if score_min and score_max and score_min > score_max:
        score_min, score_max = score_max, score_min
    if q:
        sort = "SEARCH_MATCH" if sort not in AL_SORTS else sort
    else:
        sort = sort if sort in AL_SORTS and sort != "SEARCH_MATCH" else "TRENDING_DESC"
    page = max(1, page)
    key  = (f"al:browse:{q}:{genres}:{tags}:{fmt}:{country}:{status}:{year}"
            f":{score_min}:{score_max}:{sort}:{adult}:{page}")
    return _cached(key, TTL_AL,
                   lambda: _al_browse(q, genres, tags, fmt, country, status, year,
                                      score_min, score_max, sort, adult, page))


def _al_browse(q, genres, tags, fmt, country, status, year, score_min, score_max,
               sort, adult, page):
    v = {
        "page":      page,
        "perPage":   AL_PER_PAGE,
        "sort":      [sort],
        "format_in": [fmt] if fmt else sorted(AL_FORMATS),
    }
    if q:        v["search"]    = q
    if genres:   v["genre_in"]  = list(genres)
    if tags:     v["tag_in"]    = list(tags)
    if status:   v["status_in"] = list(status)
    if country:  v["country"]   = country
    if year:
        # FuzzyDateInt is YYYYMMDD; month/day 00 sit just before the first / after the last day
        v["sd_gt"] = year * 10000
        v["sd_lt"] = (year + 1) * 10000
    # AniList's averageScore_greater / _lesser leave the number itself out, so
    # "7.0 and up" (70) asks for greater than 69, and "up to 8.0" (80) for less than 81
    if score_min:           v["score_gt"] = score_min - 1
    if score_max and score_max < 100:
        v["score_lt"] = score_max + 1
    if not adult:
        v["adult"] = False          # left out when asked for, which allows both

    data  = _al_request(_AL_BROWSE_Q, v)["Page"]
    info_ = data.get("pageInfo") or {}
    return {
        "results":  [_al_card(m) for m in data.get("media") or []],
        "hasMore":  bool(info_.get("hasNextPage")),
        "nextPage": page + 1,
    }


# ── AniList tags (the tag filter) ───────────────────────────────────────────
# AniList has a few hundred tags (Isekai, School, Villainess, ...), far too many to
# hard-code, and they get new ones. The list is asked for once and kept in
# al_tags.json for a week; if AniList can't be reached the old copy is used.

def _al_clean_tags(tags):
    """Tag names from the panel: strings, no oddities, no repeats, a sane number."""
    out = []
    for t in tags or ():
        t = re.sub(r"\s+", " ", str(t)).strip()
        if 0 < len(t) <= 60 and "|" not in t and t not in out:
            out.append(t)
    return tuple(out[:AL_TAG_MAX])


def _tags_read_file():
    try:
        with open(TAGS_FILE) as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("tags"), list):
            return data
    except (OSError, ValueError):
        pass
    return None


def _tags_fetch():
    rows = _al_request(_AL_TAGS_Q, {})["MediaTagCollection"] or []
    tags = [{"name": t["name"], "category": t.get("category") or "", "isAdult": bool(t.get("isAdult"))}
            for t in rows if t.get("name") and not t.get("isGeneralSpoiler")]
    tags.sort(key=lambda t: (t["category"], t["name"].lower()))
    return tags


def al_tags():
    """[{name, category, isAdult}] for the tag filter (general spoiler tags left out)."""
    def load():
        saved = _tags_read_file()
        if saved and time.time() - float(saved.get("fetchedAt") or 0) < TTL_AL_TAGS:
            return saved["tags"]
        try:
            tags = _tags_fetch()
        except Exception:
            if saved:                       # AniList is down: an old list beats no list
                return saved["tags"]
            raise
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            tmp = TAGS_FILE + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"fetchedAt": time.time(), "tags": tags}, f)
            os.replace(tmp, TAGS_FILE)
        except OSError:
            pass
        return tags
    return {"tags": _cached("al:tags", 3600, load)}


def al_media(aid):
    return _cached(f"al:media:{aid}", TTL_AL_INFO,
                   lambda: _al_request(_AL_MEDIA_Q, {"id": int(aid)})["Media"])


# ── AniList account (login) ─────────────────────────────────────────────────
# AniList's implicit grant (https://docs.anilist.co/guide/auth/implicit): the browser is sent
# to /oauth/authorize?client_id=..&response_type=token and AniList sends it back to the
# redirect URL set on the app (anilist.co/settings/developer) with the token in the URL
# *fragment*, which a server never sees. So the redirect URL is a page of this server
# (AL_REDIRECT); its script reads the fragment and hands the token to POST /al/auth/token.
# No client secret is involved, so nothing secret ships with the shell.
#
# The token is checked against AniList (Viewer) before it is kept, and is kept only in
# anilist_auth.json (mode 600). No endpoint ever returns it. A login attempt has a nonce that
# only the panel (the /al/auth/start reply) and the callback page know, so a web page cannot
# log the shell in to someone else's account; a request from another origin or host is refused.
#
# Fallback when the redirect cannot be used: set the app's redirect URL to
# https://anilist.co/api/v2/oauth/pin and paste the token the pin page shows into the panel.

AL_CLIENT_ID   = ""        # the project's own AniList app, if it ever has one; else each user's
AL_AUTH_FILE   = os.path.join(DATA_DIR, "anilist_auth.json")
AL_AUTHORIZE   = "https://anilist.co/api/v2/oauth/authorize"
AL_REDIRECT    = f"http://127.0.0.1:{PORT}/al/auth/callback"
AL_PENDING_TTL = 600       # seconds a started login stays open

_AL_VIEWER_Q = """
query { Viewer { id name siteUrl avatar { large medium } mediaListOptions { scoreFormat } } }
"""

_auth_lock    = threading.Lock()
_auth_pending = {"nonce": "", "at": 0.0}


class AuthError(Exception):
    def __init__(self, msg, status=400):
        super().__init__(msg)
        self.status = status


def _auth_read():
    try:
        with open(AL_AUTH_FILE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _auth_write(data):
    os.makedirs(os.path.dirname(AL_AUTH_FILE), exist_ok=True)
    tmp = AL_AUTH_FILE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        os.fchmod(f.fileno(), 0o600)
        json.dump(data, f)
    os.replace(tmp, AL_AUTH_FILE)


def _jwt_exp(token):
    """The `exp` (unix seconds) of an AniList token, or 0 if it can't be read."""
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return int(json.loads(base64.urlsafe_b64decode(part)).get("exp") or 0)
    except Exception:
        return 0


def _auth_live():
    """The saved login while its token has not run out, else {}."""
    data = _auth_read()
    if not data.get("token"):
        return {}
    exp = data.get("expiresAt") or 0
    if exp and exp < time.time():
        return {}
    return data


def al_token():
    """The bearer token for requests made as the user, or None when nobody is logged in."""
    return _auth_live().get("token") or None


def _client_id():
    cid = str(_auth_read().get("clientId") or os.environ.get("SEKAIPOP_ANILIST_CLIENT_ID")
              or AL_CLIENT_ID or "").strip()
    return cid if re.fullmatch(r"\d{1,10}", cid) else ""


def auth_status():
    with _auth_lock:
        data, live = _auth_read(), _auth_live()
    viewer = dict(live["viewer"]) if live and isinstance(live.get("viewer"), dict) else None
    if viewer and viewer.get("avatar"):
        viewer["avatar"] = proxy_url(viewer["avatar"])      # like the covers: through /image
    return {
        "loggedIn":    bool(live),
        "expired":     bool(data.get("token")) and not live,
        "hasClientId": bool(_client_id()),
        "redirectUri": AL_REDIRECT,
        "viewer":      viewer,
    }


def auth_set_client(client_id):
    cid = str(client_id or "").strip()
    if not re.fullmatch(r"\d{1,10}", cid):
        raise AuthError("The client ID is the number AniList shows for your app")
    with _auth_lock:
        data = _auth_read()
        data["clientId"] = cid
        _auth_write(data)
    return auth_status()


def auth_start():
    cid = _client_id()
    if not cid:
        raise AuthError("Enter your AniList client ID first")
    nonce = secrets.token_urlsafe(16)
    with _auth_lock:
        _auth_pending.update(nonce=nonce, at=time.time())
    return {"url": f"{AL_AUTHORIZE}?client_id={cid}&response_type=token",
            "nonce": nonce, "redirectUri": AL_REDIRECT}


def _nonce_ok(nonce):
    with _auth_lock:
        good, at = _auth_pending["nonce"], _auth_pending["at"]
    return (bool(good) and time.time() - at < AL_PENDING_TTL
            and isinstance(nonce, str) and hmac.compare_digest(nonce, good))


def auth_token(token, nonce):
    """Keep a token AniList accepts. Needs the nonce of a login started here."""
    if not _nonce_ok(nonce):
        raise AuthError("This login was not started from the panel, or it timed out. "
                        "Start it again from the panel.", 403)
    token = re.sub(r"\s+", "", str(token or ""))
    if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{20,4096}", token):
        raise AuthError("That doesn't look like an AniList token")
    try:
        viewer = (_al_request(_AL_VIEWER_Q, {}, token) or {}).get("Viewer")
    except AniListAuthError:
        raise AuthError("AniList did not accept that token")
    except Exception as e:
        raise AuthError("Could not check the token with AniList: %s" % e, 502)
    if not viewer or not viewer.get("id"):
        raise AuthError("AniList did not accept that token")
    av = viewer.get("avatar") or {}
    with _auth_lock:
        data = _auth_read()
        data.update({
            "token":     token,
            "expiresAt": _jwt_exp(token),
            "viewer": {
                "id":          viewer["id"],
                "name":        viewer.get("name") or "",
                "avatar":      av.get("large") or av.get("medium") or "",
                "siteUrl":     viewer.get("siteUrl") or "",
                "scoreFormat": (viewer.get("mediaListOptions") or {}).get("scoreFormat") or "",
            },
        })
        _auth_write(data)
        _auth_pending.update(nonce="", at=0.0)      # one login per start
    return auth_status()


def auth_forget(token=None):
    """Drop the saved token (and who it was), keeping the client ID. With `token`, only if it
    is the saved one, so a late failure of an old request can't log a new login out."""
    with _auth_lock:
        data = _auth_read()
        if not data.get("token") or (token and data.get("token") != token):
            return
        for k in ("token", "expiresAt", "viewer"):
            data.pop(k, None)
        try:
            _auth_write(data)
        except OSError:
            pass


def auth_logout():
    auth_forget()
    with _auth_lock:
        _auth_pending.update(nonce="", at=0.0)
    return auth_status()


# ── AniList tracking (the logged-in user's list) ─────────────────────────────
# The panel tells us how far a title has been read ("progress": the highest chapter number read,
# "volumes": the highest volume, for a series WeebCentral lists by volume) and we put it on the
# user's AniList list, the way Mihon / Seanime do:
#   - /al/track/progress only ever moves the numbers up (reading an old chapter again, or
#     marking one unread, never lowers what AniList has) and starts the entry: a title that is
#     not on the list, or is Planning / Paused / Dropped, becomes Reading; reaching the last
#     chapter AniList knows makes it Completed;
#   - /al/track/set is the user choosing by hand (status, progress), and may lower.
# All of it needs the login of /al/auth/*, and answers the panel only (_local_only).

AL_LIST_STATUSES = ("CURRENT", "PLANNING", "COMPLETED", "DROPPED", "PAUSED", "REPEATING")
AL_TRACK_MAX     = 100000

_AL_ENTRY_FIELDS = "id status score score100:score(format:POINT_100) progress progressVolumes"

_AL_TRACK_Q = """
query ($id:Int) {
  Media(id:$id, type:MANGA) { id chapters volumes siteUrl mediaListEntry { %s } }
}
""" % _AL_ENTRY_FIELDS


def _track_login():
    token = al_token()
    if not token:
        raise AuthError("Log in to AniList first", 401)
    return token


def _track_request(query, variables):
    token = _track_login()
    try:
        return _al_request(query, variables, token)
    except AniListAuthError as e:
        raise AuthError(str(e), 401)


def _track_view(media):
    media = media or {}
    e = media.get("mediaListEntry")
    return {
        "anilistId": media.get("id") or 0,
        "chapters":  media.get("chapters") or 0,
        "volumes":   media.get("volumes") or 0,
        "siteUrl":   media.get("siteUrl") or "",
        "entry": ({
            "status":          e.get("status") or "",
            "score":           e.get("score") or 0,       # in the user's own score format
            "score100":        e.get("score100") or 0,    # the same on a 0-100 scale
            "progress":        e.get("progress") or 0,
            "progressVolumes": e.get("progressVolumes") or 0,
        } if e else None),
    }


def _track_int(v, name):
    try:
        n = int(v)
    except (TypeError, ValueError):
        raise AuthError("%s must be a whole number" % name, 400)
    if n < 0 or n > AL_TRACK_MAX:
        raise AuthError("%s is out of range" % name, 400)
    return n


def _track_media_id(aid):
    aid = str(aid or "")
    if not aid.isdigit():
        raise AuthError("missing or bad anilistId", 400)
    return int(aid)


def al_track_info(aid):
    media = _track_request(_AL_TRACK_Q, {"id": _track_media_id(aid)}).get("Media")
    return _track_view(media)


def _track_save(mid, fields):
    """SaveMediaListEntry with only the fields given (a field left out is left alone on AniList)."""
    types = {"status": "MediaListStatus", "progress": "Int", "progressVolumes": "Int"}
    names = [k for k in types if k in fields]
    decl  = "".join(", $%s:%s" % (k, types[k]) for k in names)
    args  = "".join(", %s:$%s" % (k, k) for k in names)
    q = ("mutation ($mediaId:Int%s) { SaveMediaListEntry(mediaId:$mediaId%s) { %s } }"
         % (decl, args, _AL_ENTRY_FIELDS))
    data = _track_request(q, dict({"mediaId": mid}, **{k: fields[k] for k in names}))
    _cache_drop("al:list:")                # the Library's copy of the list is out of date now
    _cache_drop("al:activity:")            # and a new update is a new day on the heatmap
    return data.get("SaveMediaListEntry") or {}


def al_track_progress(aid, progress, volumes=0):
    """Tell AniList how far the title has been read. Never lowers what it has."""
    mid      = _track_media_id(aid)
    progress = _track_int(progress or 0, "progress")
    volumes  = _track_int(volumes or 0, "volumes")
    cur      = al_track_info(mid)
    entry    = cur["entry"] or {}
    fields   = {}
    if progress > (entry.get("progress") or 0):
        fields["progress"] = progress
    if volumes > (entry.get("progressVolumes") or 0):
        fields["progressVolumes"] = volumes
    new_progress = fields.get("progress", entry.get("progress") or 0)
    status = entry.get("status") or ""
    if progress > 0 or volumes > 0:
        if status in ("", "PLANNING", "PAUSED", "DROPPED"):
            fields["status"] = "CURRENT"
        if cur["chapters"] and new_progress >= cur["chapters"] and status not in ("COMPLETED", "REPEATING"):
            fields["status"] = "COMPLETED"
    if not fields:
        cur["changed"] = False
        return cur
    saved = _track_save(mid, fields)
    cur["entry"] = {
        "status":          saved.get("status") or fields.get("status") or status,
        "score":           saved.get("score", entry.get("score") or 0) or 0,
        "score100":        saved.get("score100", entry.get("score100") or 0) or 0,
        "progress":        saved.get("progress", new_progress) or 0,
        "progressVolumes": saved.get("progressVolumes", fields.get("progressVolumes", entry.get("progressVolumes") or 0)) or 0,
    }
    cur["changed"] = True
    return cur


def al_track_set(aid, status=None, progress=None, volumes=None):
    """The user's own choice, from the track sheet: exactly these values, lower or not."""
    mid    = _track_media_id(aid)
    fields = {}
    if status not in (None, ""):
        if status not in AL_LIST_STATUSES:
            raise AuthError("unknown status", 400)
        fields["status"] = status
    if progress is not None:
        fields["progress"] = _track_int(progress, "progress")
    if volumes is not None:
        fields["progressVolumes"] = _track_int(volumes, "volumes")
    if not fields:
        raise AuthError("nothing to set", 400)
    _track_save(mid, fields)
    out = al_track_info(mid)
    out["changed"] = True
    return out


# ── The user's own AniList lists (the Library's Reading / Completed / Dropped / Planning) ──
# AniList's MediaListCollection gives every entry of the logged-in user with its media. The whole
# collection is fetched once (in chunks of 500) and kept for a minute, then one status at a time
# is cut out of it, filtered and sorted here, so changing a tab, a filter or a sort asks AniList
# for nothing. A save of the track sheet / "update as I read" drops the copy. Custom lists are
# left out (an entry is in its status list as well). Answers the panel only (_local_only).

AL_LIST_FORMATS = {"MANGA", "ONE_SHOT", "NOVEL"}
AL_LIST_SORTS   = {"SCORE", "TITLE", "PROGRESS", "UPDATED", "ADDED"}
TTL_AL_LIST     = 60
AL_LIST_CHUNK   = 500
AL_LIST_CHUNKS  = 20            # at most 10 000 entries, so a bad reply cannot loop for ever

_AL_LIST_Q = """
query ($uid:Int,$chunk:Int,$perChunk:Int) {
  MediaListCollection(userId:$uid, type:MANGA, chunk:$chunk, perChunk:$perChunk,
                      forceSingleCompletedList:true) {
    hasNextChunk
    lists {
      status isCustomList
      entries {
        id status score score100:score(format:POINT_100) progress progressVolumes updatedAt createdAt
        media { id title{romaji english native} coverImage{large extraLarge} format status
                chapters volumes genres countryOfOrigin startDate{year} averageScore tags{name} }
      }
    }
  }
}
"""


def _list_user_id():
    viewer = _auth_live().get("viewer")
    uid = viewer.get("id") if isinstance(viewer, dict) else 0
    if not uid:
        raise AuthError("Log in to AniList first", 401)
    return int(uid)


def _al_list_fetch(uid):
    """{status: [entry, ...]} for the whole list, from AniList."""
    out, seen = {}, set()
    for chunk in range(1, AL_LIST_CHUNKS + 1):
        data = _track_request(_AL_LIST_Q, {"uid": uid, "chunk": chunk, "perChunk": AL_LIST_CHUNK})
        col = (data or {}).get("MediaListCollection") or {}
        for lst in col.get("lists") or []:
            if lst.get("isCustomList"):
                continue
            for e in lst.get("entries") or []:
                if not (e.get("media") or {}).get("id") or e.get("id") in seen:
                    continue
                seen.add(e.get("id"))
                out.setdefault(e.get("status") or lst.get("status") or "", []).append(e)
        if not col.get("hasNextChunk"):
            break
    return out


def _al_list_type(m):
    fmt = m.get("format") or ""
    if fmt == "ONE_SHOT":
        return "ONE-SHOT"
    if fmt == "NOVEL":
        return "NOVEL"
    return _AL_TYPE_LABEL.get(m.get("countryOfOrigin"), "MANGA")


def _al_list_row(e):
    m = e.get("media") or {}
    c = m.get("coverImage") or {}
    cover = c.get("large") or c.get("extraLarge") or ""
    return {
        "id":              f"al:{m['id']}",
        "anilistId":       m["id"],
        "title":           _al_title(m),
        "image":           proxy_url(cover) if cover else "",
        "type":            _al_list_type(m),
        "status":          _AL_STATUS_LABEL.get(m.get("status"), ""),
        "year":            (m.get("startDate") or {}).get("year") or 0,
        "genres":          m.get("genres") or [],
        "avg":             m.get("averageScore") or 0,
        "score":           e.get("score") or 0,          # in the user's own score format
        "score100":        e.get("score100") or 0,       # the same on a 0-100 scale
        "progress":        e.get("progress") or 0,
        "progressVolumes": e.get("progressVolumes") or 0,
        "chapters":        m.get("chapters") or 0,
        "volumes":         m.get("volumes") or 0,
        "updatedAt":       e.get("updatedAt") or 0,
        "createdAt":       e.get("createdAt") or 0,
        "listStatus":      e.get("status") or "",
    }


def _al_list_match(e, q, fmt, country, genres, tags, year, mstatus):
    m = e.get("media") or {}
    if fmt and (m.get("format") or "") != fmt:
        return False
    if country and m.get("countryOfOrigin") != country:
        return False
    if year and ((m.get("startDate") or {}).get("year") or 0) != year:
        return False
    if mstatus and (m.get("status") or "") not in mstatus:
        return False
    # like AniList's own filters: every genre / tag asked for has to be on the title
    have = set(m.get("genres") or [])
    if any(g not in have for g in genres):
        return False
    have = {t.get("name") for t in m.get("tags") or []}
    if any(t not in have for t in tags):
        return False
    if q:
        t = m.get("title") or {}
        if not any(q in (t.get(k) or "").casefold() for k in ("english", "romaji", "native")):
            return False
    return True


def _al_list_sorted(rows, sort):
    if sort == "TITLE":
        return sorted(rows, key=lambda r: r["title"].casefold())
    by = {"SCORE": "score100", "PROGRESS": "progress", "UPDATED": "updatedAt", "ADDED": "createdAt"}[sort]
    # biggest first; ties, and the unscored, in title order
    return sorted(rows, key=lambda r: (-r[by], r["title"].casefold()))


def al_list(status="CURRENT", q="", fmt="", country="", genres=(), tags=(), year=0,
            mstatus=(), sort="SCORE"):
    status = status or "CURRENT"
    if status not in AL_LIST_STATUSES:
        raise AuthError("unknown status", 400)
    if fmt and fmt not in AL_LIST_FORMATS:
        raise AuthError("unknown format", 400)
    country = country if country in AL_COUNTRIES else ""
    genres  = tuple(g for g in genres if g in AL_GENRES)
    tags    = _al_clean_tags(tags)
    year    = year if 1900 <= year <= 2100 else 0
    if isinstance(mstatus, str):
        mstatus = [x for x in mstatus.split(",") if x]
    mstatus = {x for x in mstatus if x in AL_STATUSES}
    sort    = sort if sort in AL_LIST_SORTS else "SCORE"
    q       = re.sub(r"\s+", " ", q or "").strip().casefold()

    uid = _list_user_id()
    by_status = _cached(f"al:list:{uid}", TTL_AL_LIST, lambda: _al_list_fetch(uid))
    kept = [_al_list_row(e) for e in by_status.get(status, [])
            if _al_list_match(e, q, fmt, country, genres, tags, year, mstatus)]
    viewer = _auth_live().get("viewer") or {}
    return {
        "status":      status,
        "counts":      {s: len(by_status.get(s, [])) for s in AL_LIST_STATUSES},
        "total":       len(kept),
        "scoreFormat": viewer.get("scoreFormat") or "",
        "entries":     _al_list_sorted(kept, sort),
    }


# ── AniList profile (the page behind the avatar key) ───────────────────────
# Who the user is on AniList (banner, avatar), what they have read (the manga statistics) and
# the manga they hearted (their favourites). One request, kept two minutes; the panel shows
# the favourites as covers and opens a title like any other card.

TTL_AL_PROFILE = 120
AL_FAV_ASKED   = 24             # asked from AniList (novels are dropped, they have their own reader)
AL_FAV_SHOWN   = 16
AL_ABOUT_MAX   = 700            # characters of the bio shown (the rest is on AniList)

_AL_PROFILE_Q = """
query ($perPage:Int, $uid:Int!) {
  Viewer {
    id name siteUrl bannerImage about
    avatar { large medium }
    statistics { manga { count chaptersRead volumesRead meanScore
      genres(limit:8, sort:COUNT_DESC) { genre count meanScore }
    } }
    favourites { manga(page:1, perPage:$perPage) {
      pageInfo { total }
      nodes { %s }
    } }
  }
  followers: Page(perPage:1) { pageInfo { total } followers(userId:$uid) { id } }
  following: Page(perPage:1) { pageInfo { total } following(userId:$uid) { id } }
}
""" % _AL_CARD


def _al_plain_text(raw, limit=AL_ABOUT_MAX):
    """AniList's bio is Markdown with a few HTML tags of its own (img###(url), ~!spoilers!~,
    ~~~centered~~~, <br>): the panel shows it as plain text, so those are taken out."""
    t = str(raw or "")
    t = re.sub(r"(?i)<br\s*/?>", "\n", t)
    t = re.sub(r"(?is)<(script|style).*?</\1>", " ", t)
    t = re.sub(r"(?i)\b(?:img|webm|youtube)\d*\(\s*[^)]*\)", " ", t)      # img220(url), webm(url), youtube(url)
    t = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", t)                          # ![alt](url)
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)                      # [text](url) -> text
    t = re.sub(r"~!.*?!~", " ", t, flags=re.S)                             # spoilers stay hidden
    t = t.replace("~~~", " ")
    t = re.sub(r"<[^>]+>", " ", t)
    t = re.sub(r"https?://\S+", " ", t)
    t = re.sub(r"(?m)^[ \t]{0,3}#{1,6}[ \t]*", "", t)
    t = re.sub(r"[*_`]{1,3}", "", t)
    t = re.sub(r"[ \t\u00a0]+", " ", t)
    t = re.sub(r"\s*\n\s*(?:\n\s*)+", "\n\n", t).strip()
    t = re.sub(r" *\n *", "\n", t)
    if len(t) > limit:
        t = t[:limit].rsplit(" ", 1)[0].rstrip(".,;:- \n") + "\u2026"
    return t


def _al_profile_fetch(uid=0):
    data = _track_request(_AL_PROFILE_Q, {"perPage": AL_FAV_ASKED, "uid": int(uid or 0)})
    v     = (data or {}).get("Viewer") or {}
    stats = ((v.get("statistics") or {}).get("manga")) or {}
    favs  = ((v.get("favourites") or {}).get("manga")) or {}
    nodes = [m for m in (favs.get("nodes") or [])
             if m and m.get("id") and m.get("format") != "NOVEL"]
    av     = v.get("avatar") or {}
    avatar = av.get("large") or av.get("medium") or ""
    banner = v.get("bannerImage") or ""
    _auth_update_viewer(v)

    def num(x):
        try:
            return float(x or 0)
        except (TypeError, ValueError):
            return 0.0

    def total(key):
        return int(num(((data or {}).get(key) or {}).get("pageInfo", {}).get("total")))

    genres = [{"genre": g.get("genre") or "", "count": int(num(g.get("count"))),
               "meanScore": num(g.get("meanScore"))}
              for g in (stats.get("genres") or []) if g and g.get("genre")]

    return {
        "name":    v.get("name") or "",
        "siteUrl": v.get("siteUrl") or "",
        "avatar":  proxy_url(avatar) if avatar else "",
        "banner":  proxy_url(banner) if banner else "",
        "stats": {
            "count":        int(num(stats.get("count"))),
            "chaptersRead": int(num(stats.get("chaptersRead"))),
            "volumesRead":  int(num(stats.get("volumesRead"))),
            "meanScore":    num(stats.get("meanScore")),       # 0-100, whatever the score format
        },
        "favouritesTotal": int(num((favs.get("pageInfo") or {}).get("total"))),
        "favourites":      [_al_card(m) for m in nodes[:AL_FAV_SHOWN]],
        "about":           _al_plain_text(v.get("about")),
        "followers":       total("followers"),
        "following":       total("following"),
        "genres":          genres,                  # most read first, from AniList's statistics
    }


def _auth_update_viewer(v):
    """Keep the name, avatar and link saved with the login in step with AniList. They were
    written once, when the login was made, so a new avatar never reached the header key."""
    with _auth_lock:
        data = _auth_read()
        cur = data.get("viewer")
        if not data.get("token") or not isinstance(cur, dict) or cur.get("id") != v.get("id"):
            return
        av  = v.get("avatar") or {}
        new = dict(cur)
        new["name"]    = v.get("name") or cur.get("name") or ""
        new["avatar"]  = av.get("large") or av.get("medium") or cur.get("avatar") or ""
        new["siteUrl"] = v.get("siteUrl") or cur.get("siteUrl") or ""
        if new != cur:
            data["viewer"] = new
            try:
                _auth_write(data)
            except OSError:
                pass


def al_profile(fresh=False):
    uid = _list_user_id()
    if fresh:                       # the page just opened: what AniList has now, not two minutes ago
        _cache_drop(f"al:profile:{uid}")
    return _cached(f"al:profile:{uid}", TTL_AL_PROFILE, lambda: _al_profile_fetch(uid))


# ── What the profile page builds from the list (no new question to AniList) ──
# Reading now, Top rated and the random Planning pick are cut out of the same copy of the list
# the Library tabs use (kept 60 s, dropped by a save), so they cost nothing extra.

AL_READING_SHOWN = 40
AL_TOP_SHOWN     = 16
AL_SHELF_SHOWN   = 16           # Almost done, Stalled and the Planning shelf
AL_ALMOST_LEFT   = 5            # "almost done": this many chapters or fewer to go
AL_STALLED_DAYS  = 30           # "stalled": a Reading title not touched for this long


def al_overview():
    uid = _list_user_id()
    by_status = _cached(f"al:list:{uid}", TTL_AL_LIST, lambda: _al_list_fetch(uid))
    viewer = _auth_live().get("viewer") or {}

    # what is being read, the most recently touched first (the list's own "updated" time)
    reading = [_al_list_row(e) for e in by_status.get("CURRENT", [])]
    reading.sort(key=lambda r: (-r["updatedAt"], r["title"].casefold()))

    # the highest scored of every list; ties go to the one scored most recently
    scored = [_al_list_row(e) for es in by_status.values() for e in es
              if (e.get("score100") or 0) > 0]
    scored.sort(key=lambda r: (-r["score100"], -r["updatedAt"], r["title"].casefold()))

    fmt = viewer.get("scoreFormat") or ""
    now = int(time.time())

    # Reading titles a few chapters from the end of what AniList knows (needs a known total and
    # a start; a title with no total is never "almost done"). The fewest left first.
    almost = []
    for r in reading:
        left = r["chapters"] - r["progress"]
        if r["chapters"] > 0 and r["progress"] > 0 and 0 < left <= AL_ALMOST_LEFT:
            almost.append(dict(r, left=left))
    almost.sort(key=lambda r: (r["left"], -r["updatedAt"], r["title"].casefold()))

    # Reading titles whose list entry has not changed for AL_STALLED_DAYS (an entry AniList gives
    # no time for is left out, not called stalled). The longest idle first.
    stalled = []
    for r in reading:
        if r["updatedAt"] > 0 and now - r["updatedAt"] >= AL_STALLED_DAYS * 86400:
            stalled.append(dict(r, idleDays=(now - r["updatedAt"]) // 86400))
    stalled.sort(key=lambda r: (r["updatedAt"], r["title"].casefold()))

    # the Planning list as a "what next" shelf: AniList's own average first, the unrated last
    planning = [_al_list_row(e) for e in by_status.get("PLANNING", [])]
    planning.sort(key=lambda r: (-r["avg"], r["title"].casefold()))

    return {
        "counts":       {s: len(by_status.get(s, [])) for s in AL_LIST_STATUSES},
        "scoreFormat":  fmt,
        "reading":      reading[:AL_READING_SHOWN],
        "readingTotal": len(reading),
        "top":          scored[:AL_TOP_SHOWN],
        "scoreDist":    _al_score_dist(by_status, fmt),
        "almostDone":   almost[:AL_SHELF_SHOWN],
        "almostTotal":  len(almost),
        "stalled":      stalled[:AL_SHELF_SHOWN],
        "stalledTotal": len(stalled),
        "planning":     planning[:AL_SHELF_SHOWN],
        "planningTotal": len(planning),
        "mix":          _al_mix(by_status),
    }


AL_DECADE_FLOOR = 1990          # decades older than this are one bar: "Before 1990"


def _al_mix(by_status):
    """What the read part of the list is made of: how many titles of each type (manga, manhwa,
    manhua, one-shot, novel) and of each decade they started in. Planning is left out: those
    are not read yet. From the list already held, so it asks AniList for nothing."""
    types, decades, older = {}, {}, 0
    for status, es in by_status.items():
        if status == "PLANNING":
            continue
        for e in es:
            m = e.get("media") or {}
            label = _al_list_type(m)
            types[label] = types.get(label, 0) + 1
            y = (m.get("startDate") or {}).get("year") or 0
            if y <= 0:
                continue
            if y < AL_DECADE_FLOOR:
                older += 1
            else:
                d = y // 10 * 10
                decades[d] = decades.get(d, 0) + 1
    rows = [{"label": f"{d}s", "count": decades[d]} for d in sorted(decades, reverse=True)]
    if older:
        rows.append({"label": f"Before {AL_DECADE_FLOOR}", "count": older})
    return {"types": [{"label": k, "count": v} for k, v in sorted(types.items(), key=lambda kv: (-kv[1], kv[0]))],
            "decades": rows}


def _al_score_dist(by_status, fmt):
    """How the user's scores spread: {"max": 10, "counts": [n of score 1, ... n of score max]}.
    The scale follows their score format (10 for the 10 and 100 point formats and the decimal one,
    5 for stars, 3 for smileys); a decimal score goes to the nearest whole point, a 100-point score
    to the nearest ten. Unscored titles are not counted."""
    top = {"POINT_5": 5, "POINT_3": 3}.get(fmt, 10)
    counts = [0] * top
    for es in by_status.values():
        for e in es:
            if fmt in ("POINT_5", "POINT_3", "POINT_10", "POINT_10_DECIMAL"):
                v = e.get("score") or 0
            else:                                   # POINT_100, or a format we were not told
                v = (e.get("score100") or 0) / 10
            if v <= 0:
                continue
            counts[min(top, max(1, int(v + 0.5))) - 1] += 1
    return {"max": top, "counts": counts}


def al_pick(exclude=""):
    """One random title of the Planning list. `exclude` is the AniList id of the one on screen,
    so \"Not this one\" never answers with the same title (unless it is the only one)."""
    uid = _list_user_id()
    by_status = _cached(f"al:list:{uid}", TTL_AL_LIST, lambda: _al_list_fetch(uid))
    planning = by_status.get("PLANNING", [])
    pool = [e for e in planning if str((e.get("media") or {}).get("id")) != str(exclude)] or planning
    viewer = _auth_live().get("viewer") or {}
    return {
        "total":       len(planning),
        "scoreFormat": viewer.get("scoreFormat") or "",
        "entry":       _al_list_row(random.choice(pool)) if pool else None,
    }


# ── Reading activity (the heatmap on the profile) ──────────────────────────
# The days the user updated a manga on AniList, from their list activity (one per update; AniList
# folds a run of updates to one title into one). Last AL_ACTIVITY_DAYS days, newest first, at
# most AL_ACTIVITY_PAGES pages of 50, kept ten minutes. {\"counts\": {\"YYYY-MM-DD\": n}, ...}
# with the days in the machine's own time zone.

TTL_AL_ACTIVITY   = 600
AL_ACTIVITY_DAYS  = 182         # 26 weeks
AL_ACTIVITY_PAGES = 6

_AL_ACTIVITY_Q = """
query ($uid:Int, $page:Int, $since:Int) {
  Page(page:$page, perPage:50) {
    pageInfo { hasNextPage }
    activities(userId:$uid, type:MANGA_LIST, createdAt_greater:$since, sort:ID_DESC) {
      ... on ListActivity { createdAt }
    }
  }
}
"""


def _al_activity_fetch(uid):
    since = int(time.time()) - AL_ACTIVITY_DAYS * 86400
    counts, total, capped = {}, 0, False
    for page in range(1, AL_ACTIVITY_PAGES + 1):
        data = _track_request(_AL_ACTIVITY_Q, {"uid": uid, "page": page, "since": since})
        pg = (data or {}).get("Page") or {}
        for a in pg.get("activities") or []:
            at = (a or {}).get("createdAt")
            if not isinstance(at, int) or at < since:
                continue
            day = time.strftime("%Y-%m-%d", time.localtime(at))
            counts[day] = counts.get(day, 0) + 1
            total += 1
        if not (pg.get("pageInfo") or {}).get("hasNextPage"):
            break
        if page == AL_ACTIVITY_PAGES:
            capped = True               # there is more than the pages asked: the oldest weeks are thin
    return {"counts": counts, "total": total, "days": AL_ACTIVITY_DAYS, "capped": capped}


def al_activity(fresh=False):
    uid = _list_user_id()
    if fresh:
        _cache_drop(f"al:activity:{uid}")
    return _cached(f"al:activity:{uid}", TTL_AL_ACTIVITY, lambda: _al_activity_fetch(uid))


# ── More for the profile page: colour, tags, staff, the activity feed, recommendations ──
# These are questions AniList is asked on top of the list. Each part is optional: if AniList
# refuses one (a field it no longer has, a hiccup) that part is left out and the rest of the
# page is not harmed. A lost login still comes through as a 401.

TTL_AL_STATS_EXTRA = 600
TTL_AL_FEED        = 120
TTL_AL_RECS        = 600
AL_TAGS_SHOWN      = 8
AL_STAFF_SHOWN     = 8
AL_FEED_ASKED      = 20
AL_FEED_SHOWN      = 12
AL_RECS_SOURCES    = 6          # the top scored titles asked about
AL_RECS_MIN_SCORE  = 70         # (0-100) a title scored lower is not something to recommend from
AL_RECS_PER        = 10         # recommendations kept for each
AL_RECS_GROUPS     = 3          # shelves of "Because you rated X highly"

# The names AniList gives a profile colour, as the hex they are drawn in on the website
AL_PROFILE_COLORS = {"blue": "#3db4f2", "purple": "#c063ff", "pink": "#fc9dd6", "orange": "#ef881a",
                     "red": "#e13333", "green": "#4cca51", "gray": "#677b94"}

_AL_STATS_EXTRA_Q = """
query {
  Viewer {
    options { profileColor }
    statistics { manga {
      tags(limit:12, sort:COUNT_DESC) { tag { name } count meanScore }
      staff(limit:10, sort:COUNT_DESC) { staff { id name { full } siteUrl } count meanScore }
    } }
  }
}
"""

_AL_FEED_Q = """
query ($uid:Int, $perPage:Int) {
  Page(page:1, perPage:$perPage) {
    activities(userId:$uid, type:MANGA_LIST, sort:ID_DESC) {
      ... on ListActivity {
        createdAt status progress
        media { id title{romaji english native} coverImage{large extraLarge} }
      }
    }
  }
}
"""

_AL_RECS_Q = """
query ($ids:[Int], $per:Int) {
  Page(page:1, perPage:20) {
    media(id_in:$ids, type:MANGA) {
      id
      recommendations(sort:RATING_DESC, perPage:$per) {
        nodes { rating mediaRecommendation { %s } }
      }
    }
  }
}
""" % _AL_CARD


def _al_num(x):
    try:
        return float(x or 0)
    except (TypeError, ValueError):
        return 0.0


def _al_profile_color(raw):
    """The profile colour as #rrggbb: one of AniList's names, or a hex it was set to. Empty if neither."""
    c = str(raw or "").strip().lower()
    if c in AL_PROFILE_COLORS:
        return AL_PROFILE_COLORS[c]
    return c if re.fullmatch(r"#[0-9a-f]{6}", c) else ""


def _optional(fn):
    """Run one optional part of the page: its answer, or None when AniList would not give it."""
    try:
        return fn()
    except AuthError:
        raise
    except Exception as e:
        print(f"[manga-server] profile extra left out: {e}", file=sys.stderr)
        return None


def _al_stats_extra_fetch():
    data  = _track_request(_AL_STATS_EXTRA_Q, {})
    v     = (data or {}).get("Viewer") or {}
    stats = ((v.get("statistics") or {}).get("manga")) or {}
    tags = [{"label": str((t.get("tag") or {}).get("name") or ""), "count": int(_al_num(t.get("count"))),
             "meanScore": _al_num(t.get("meanScore"))}
            for t in (stats.get("tags") or []) if t and (t.get("tag") or {}).get("name")]
    staff = []
    for t in stats.get("staff") or []:
        st = (t or {}).get("staff") or {}
        name = (st.get("name") or {}).get("full")
        if not (name and st.get("id")):
            continue
        url = st.get("siteUrl") or ""
        if not url.startswith("https://anilist.co/"):
            url = f"https://anilist.co/staff/{int(st['id'])}"
        staff.append({"label": str(name), "count": int(_al_num(t.get("count"))),
                      "meanScore": _al_num(t.get("meanScore")), "url": url})
    return {"color": _al_profile_color((v.get("options") or {}).get("profileColor")),
            "tags": tags[:AL_TAGS_SHOWN], "staff": staff[:AL_STAFF_SHOWN]}


def _al_feed_fetch(uid):
    """The user's latest list updates, newest first: {id, title, image, status, progress, createdAt}.
    `status` and `progress` are AniList's own words ("read chapter", "52"); the panel words them."""
    data = _track_request(_AL_FEED_Q, {"uid": uid, "perPage": AL_FEED_ASKED})
    rows = []
    for a in ((data or {}).get("Page") or {}).get("activities") or []:
        a = a or {}
        m, at = a.get("media") or {}, a.get("createdAt")
        if not m.get("id") or not isinstance(at, int):
            continue                    # an activity of another kind comes back as {}
        c = m.get("coverImage") or {}
        cover = c.get("large") or c.get("extraLarge") or ""
        rows.append({"id": f"al:{m['id']}", "title": _al_title(m),
                     "image": proxy_url(cover) if cover else "",
                     "status": str(a.get("status") or ""), "progress": str(a.get("progress") or ""),
                     "createdAt": at})
    return rows[:AL_FEED_SHOWN]


def al_extras():
    uid   = _list_user_id()
    stats = _optional(lambda: _cached(f"al:extras:{uid}", TTL_AL_STATS_EXTRA, _al_stats_extra_fetch)) or {}
    feed  = _optional(lambda: _cached(f"al:feed:{uid}", TTL_AL_FEED, lambda: _al_feed_fetch(uid))) or []
    return {"color": stats.get("color", ""), "tags": stats.get("tags", []),
            "staff": stats.get("staff", []), "feed": feed}


def _al_recs_fetch(uid):
    by_status = _cached(f"al:list:{uid}", TTL_AL_LIST, lambda: _al_list_fetch(uid))
    owned = {e["media"]["id"] for es in by_status.values() for e in es}     # on the list already
    scored = [_al_list_row(e) for es in by_status.values() for e in es
              if (e.get("score100") or 0) >= AL_RECS_MIN_SCORE]
    scored.sort(key=lambda r: (-r["score100"], -r["updatedAt"], r["title"].casefold()))
    sources = scored[:AL_RECS_SOURCES]
    if not sources:
        return {"groups": []}
    data = _track_request(_AL_RECS_Q, {"ids": [r["anilistId"] for r in sources], "per": AL_RECS_PER})
    media = {m["id"]: m for m in (((data or {}).get("Page") or {}).get("media") or []) if m and m.get("id")}

    # a title is listed once, under the source whose readers rated it highest (the earlier source on a tie)
    best = {}
    for i, src in enumerate(sources):
        for n in (((media.get(src["anilistId"]) or {}).get("recommendations") or {}).get("nodes") or []):
            rec, rating = (n or {}).get("mediaRecommendation") or {}, (n or {}).get("rating") or 0
            if not rec.get("id") or rating <= 0 or rec["id"] in owned or rec.get("format") == "NOVEL":
                continue
            if rec["id"] not in best or rating > best[rec["id"]][0]:
                best[rec["id"]] = (rating, i, rec)
    by_source = {}
    for rating, i, rec in best.values():
        by_source.setdefault(i, []).append((rating, rec))
    groups = []
    for i in sorted(by_source):
        rows = sorted(by_source[i], key=lambda t: (-t[0], -(t[1].get("averageScore") or 0), _al_title(t[1]).casefold()))
        items = []
        for rating, rec in rows[:AL_RECS_PER]:
            c = _al_card(rec)
            c["avg"], c["rating"] = c["score"], rating
            items.append(c)
        groups.append({"because": sources[i]["title"], "becauseId": sources[i]["id"], "items": items})
    solid = [g for g in groups if len(g["items"]) >= 3] or groups          # a shelf of one is not a shelf
    return {"groups": solid[:AL_RECS_GROUPS]}


def al_recs():
    uid = _list_user_id()
    out = _optional(lambda: _cached(f"al:recs:{uid}", TTL_AL_RECS, lambda: _al_recs_fetch(uid)))
    return out or {"groups": []}


_AUTH_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>SekaiPop · AniList</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 16px/1.5 system-ui, sans-serif; background: #14161f; color: #eceef6;
         display: grid; place-items: center; min-height: 100vh; margin: 0; }
  main { max-width: 26rem; padding: 2rem; text-align: center; }
  h1 { font-size: 1.3rem; margin: 0 0 .6rem; }
  p { margin: 0; opacity: .8; }
  .err h1 { color: #ff8a9c; }
</style></head><body><main id="m"><h1 id="t">Finishing the AniList login…</h1><p id="d"></p></main>
<noscript><p>This page needs JavaScript to finish the login.</p></noscript>
<script>
(function () {
  var nonce = %(nonce)s;
  var t = document.getElementById("t"), d = document.getElementById("d");
  function fail(msg) { document.getElementById("m").className = "err"; t.textContent = "Login not finished"; d.textContent = msg; }
  var h = new URLSearchParams(location.hash.replace(/^#/, ""));
  var q = new URLSearchParams(location.search);
  var token = h.get("access_token");
  history.replaceState(null, "", location.pathname);        // the token leaves the address bar and history
  if (!token) return fail(q.get("error_description") || h.get("error") || q.get("error")
                          || "AniList sent no token. Start the login again from the panel.");
  fetch("/al/auth/token", { method: "POST", headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ token: token, nonce: nonce }) })
    .then(function (r) { return r.json(); })
    .then(function (j) {
      if (j.error) return fail(j.error);
      t.textContent = "Logged in" + (j.viewer && j.viewer.name ? " as " + j.viewer.name : "");
      d.textContent = "You can close this tab and go back to the manga panel.";
    })
    .catch(function () { fail("Could not reach SekaiPop. Is the manga panel open?"); });
})();
</script></body></html>
"""


def auth_callback_html():
    with _auth_lock:
        nonce = _auth_pending["nonce"] if time.time() - _auth_pending["at"] < AL_PENDING_TTL else ""
    return _AUTH_PAGE % {"nonce": json.dumps(nonce)}



def _al_text(s):
    s = re.sub(r"<br\s*/?>", " ", s or "", flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", _html.unescape(s)).strip()


def _al_authors(m):
    names = []
    for e in ((m.get("staff") or {}).get("edges") or []):
        if not re.search(r"story|art|original|creator", e.get("role") or "", re.I):
            continue
        n = ((e.get("node") or {}).get("name") or {}).get("full")
        if n and n not in names:
            names.append(n)
    return names


_AL_STATUS_NICE = {
    "RELEASING": "Ongoing", "FINISHED": "Completed", "NOT_YET_RELEASED": "Not yet released",
    "CANCELLED": "Cancelled", "HIATUS": "On hiatus",
}
_AL_LANGUAGE = {"JP": "Japanese", "KR": "Korean", "CN": "Chinese", "TW": "Chinese"}
_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def _al_date(d):
    """AniList's {year, month, day} (any part may be null) as \"Mar 4, 2019\" / \"Mar 2019\" / \"2019\"."""
    d = d or {}
    y, mo, day = d.get("year"), d.get("month"), d.get("day")
    if not y:
        return ""
    if mo and 1 <= mo <= 12:
        return f"{_MONTHS[mo - 1]} {day}, {y}" if day else f"{_MONTHS[mo - 1]} {y}"
    return str(y)


def _al_alt_names(m):
    """Every other name the title goes by (English, romaji, native, then AniList's synonyms)."""
    t = m.get("title") or {}
    shown = _norm(_al_title(m))
    out, seen = [], {shown}
    for raw in [t.get("english"), t.get("romaji"), t.get("native"), *(m.get("synonyms") or [])]:
        raw = (raw or "").strip()
        n = _norm(raw)
        if raw and n and n not in seen:
            seen.add(n)
            out.append(raw)
    return out


def _al_translation(m):
    """What AniList can say about the translation: the original language, and whether there is an
    official English release (a read-online link in English) or the title is licensed at all.
    Anything else is a fan translation. AniList does not name scanlation groups."""
    original = _AL_LANGUAGE.get(m.get("countryOfOrigin"), "")
    sites = []
    for l in m.get("externalLinks") or []:
        if (l.get("type") or "") == "STREAMING" and (l.get("language") or "").casefold() == "english" \
                and l.get("site") and l["site"] not in [x["site"] for x in sites]:
            sites.append({"site": l["site"], "url": l.get("url") or ""})
    licensed = m.get("isLicensed") is True
    if sites:
        kind, label = "official", "Official English \u00b7 " + ", ".join(x["site"] for x in sites[:3])
    elif licensed:
        kind, label = "licensed", "Licensed \u00b7 no official English link on AniList"
    else:
        kind, label = "fan", "Not licensed \u00b7 fan translation"
    return {"original": original, "kind": kind, "label": label, "sites": sites, "licensed": licensed}


def _al_tag_list(m):
    """All tags, the most fitting first; spoiler tags are marked so the panel can hide them."""
    rows = [{"name": t["name"], "rank": t.get("rank") or 0,
             "spoiler": bool(t.get("isMediaSpoiler")), "category": t.get("category") or ""}
            for t in (m.get("tags") or []) if t.get("name")]
    return sorted(rows, key=lambda r: (-r["rank"], r["name"].casefold()))


def _al_base(m):
    """Everything about a title that comes from AniList (the chapters are added after)."""
    card = _al_card(m)
    tags = [t["name"] for t in (m.get("tags") or [])
            if not t.get("isMediaSpoiler") and (t.get("rank") or 0) >= 60][:6]
    return {
        "id":            "",
        "anilistId":     m["id"],
        "title":         card["title"],
        "description":   _al_text(m.get("description")),
        "status":        card["status"],
        "statusLabel":   _AL_STATUS_NICE.get(m.get("status"), ""),
        "image":         card["image"],
        "authors":       _al_authors(m),
        "tags":          (m.get("genres") or []) + tags,
        "genres":        m.get("genres") or [],
        "tagList":       _al_tag_list(m),
        "altNames":      _al_alt_names(m),
        "year":          card["year"],
        "startDate":     _al_date(m.get("startDate")),
        "endDate":       _al_date(m.get("endDate")),
        "endYear":       (m.get("endDate") or {}).get("year") or 0,
        "score":         card["score"],
        "meanScore":     m.get("meanScore") or 0,
        "popularity":    m.get("popularity") or 0,
        "favourites":    m.get("favourites") or 0,
        "type":          card["type"],
        "translation":   _al_translation(m),
        "chaptersTotal": m.get("chapters") or 0,
        "volumesTotal":  m.get("volumes") or 0,
        "siteUrl":       m.get("siteUrl") or "",
        "chapters":      [],
    }


# ── Matching an AniList title to its WeebCentral series ─────────────────────
# AniList and WeebCentral rarely spell a title the same way: one uses the English
# name, the other a fan name; hyphens, "The", subtitles and "(Official)" differ.
# So the match works in steps, and stops at the first one that is sure enough:
#   1. search WeebCentral with every AniList name (English, romaji, synonyms, native)
#   2. search again with looser versions of those names (no punctuation, no subtitle,
#      the first few words only)
#   3. open the best few results and read their "Associated Name(s)" list: that is
#      where WeebCentral keeps the other names of a series

MAX_NAME_SEARCHES  = 5      # names tried in step 1
MAX_LOOSE_SEARCHES = 8      # extra searches in step 2
MAX_ALIAS_LOOKUPS  = 4      # series pages opened in step 3
ALIAS_MIN_SCORE    = 0.15   # results with nothing alike at all are skipped in step 3
ALIAS_EXACT_SCORE  = 0.97   # a series whose other name equals an AniList name


def _strip_brackets(s):
    return re.sub(r"\s*[\(\[\{][^)\]}]*[\)\]\}]\s*", " ", s or "").strip()


def _norm(s):
    s = unicodedata.normalize("NFKD", _html.unescape(s or ""))
    # drop accents on Latin letters only (so Japanese / Korean marks are kept)
    out = []
    for c in s:
        if unicodedata.combining(c) and out and ord(out[-1]) < 0x250:
            continue
        out.append(c)
    s = "".join(out).lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[\W_]+", " ", s).strip()
    return re.sub(r"^(the|a|an) ", "", s)


def _forms(raw):
    """The ways one name can be written: as is, and without a bracketed note."""
    out = []
    for f in (_norm(raw), _norm(_strip_brackets(raw))):
        if f and f not in out:
            out.append(f)
    return out


def _sim(a, b):
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    r = difflib.SequenceMatcher(None, a, b).ratio()
    # The same words in another order ("Heroine of S-Class" ...): close, never certain.
    ta, tb = sorted(a.split()), sorted(b.split())
    if ta != tb:
        r = max(r, 0.95 * difflib.SequenceMatcher(None, " ".join(ta), " ".join(tb)).ratio())
    else:
        r = max(r, 0.95)
    short, long_ = sorted((a, b), key=len)
    # One title inside the other ("X" and "X: Subtitle") is close, never certain:
    # a sequel or side story shares its name with the original.
    if len(short) >= 4 and f" {short} " in f" {long_} ":
        r = max(r, 0.6 + 0.4 * len(short) / len(long_))
    return r


def _best_sim(name_forms, title):
    """How alike a WeebCentral title is to the AniList names (a list of form-lists)."""
    best = 0.0
    for tf in _forms(title):
        for forms in name_forms:
            for nf in forms:
                best = max(best, _sim(nf, tf))
    return best


def _al_name_variants(m):
    """Every name AniList has, English and romaji first (those are searched first)."""
    t = m.get("title") or {}
    out, seen = [], set()
    syn = [x for x in (m.get("synonyms") or []) if x]
    latin = [x for x in syn if re.search(r"[A-Za-z]", x)]
    other = [x for x in syn if x not in latin]
    for raw in [t.get("english"), t.get("romaji"), *latin, t.get("native"), *other]:
        n = _norm(raw)
        if n and n not in seen:
            seen.add(n)
            out.append(raw)
    return out


def _query_variants(raw):
    """Looser ways to search for a name, most likely first (the name itself is not included)."""
    raw = (raw or "").strip()
    out = []

    def add(q):
        q = re.sub(r"\s+", " ", (q or "")).strip()
        if len(q) >= 2 and q.lower() != raw.lower() and q not in out:
            out.append(q)

    nob = _strip_brackets(raw)
    add(nob)
    loose = re.sub(r"[^\w\s]", " ", nob, flags=re.UNICODE)      # "S-Class" -> "S Class"
    add(loose)
    add(re.sub(r"[^\w\s]", "", nob, flags=re.UNICODE))          # "S-Class" -> "SClass"
    head = re.split(r"\s*[:：~]\s*|\s+[-–—]\s+", nob, maxsplit=1)[0]   # before a subtitle
    if head != nob:
        add(head)
    words = loose.split()
    if words and words[0].lower() in ("the", "a", "an") and len(words) > 2:
        add(" ".join(words[1:]))
    if len(words) > 4:
        add(" ".join(words[:4]))
    if len(words) > 2:
        add(" ".join(words[:3]))
    return out


def _wc_aliases(wc_id):
    """The other names WeebCentral lists for a series (its "Associated Name(s)")."""
    def load():
        html = fetch(f"{BASE}/series/{wc_id}")
        m = re.search(r"Associated Name\(s\)[\s\S]*?<ul[^>]*>([\s\S]*?)</ul>", html, re.I)
        if not m:
            return []
        names = [clean_text(x) for x in re.findall(r"<li[^>]*>([\s\S]*?)</li>", m.group(1))]
        return [n for n in names if n]
    return _cached(f"aliases:{wc_id}", TTL_INFO, load)


def _wc_candidates(m, limit=8):
    """WeebCentral series that could be this title, best first, each with a score."""
    names      = _al_name_variants(m)
    name_forms = [_forms(n) for n in names]
    year       = str((m.get("startDate") or {}).get("year") or "")
    ctype      = _WC_TYPE.get(m.get("countryOfOrigin"), "")

    found, state = {}, {"err": None}

    def best():
        return max((c["score"] for c in found.values()), default=0.0)

    def take(results):
        for r in results:
            s = _best_sim(name_forms, r["title"])
            if year and r.get("year") == year:
                s += 0.03
            if ctype and (r.get("type") or "").lower() == ctype.lower():
                s += 0.02
            s = round(min(s, 1.0), 3)
            if r["id"] not in found or s > found[r["id"]]["score"]:
                found[r["id"]] = {**r, "score": s}

    def run(q):
        """One search; 'Best Match' first, the site's own order if that finds nothing."""
        for sort in ("Best Match", "Popularity"):
            try:
                res = search(q, None, 0, sort)["results"]
            except Exception as e:
                state["err"] = e
                continue
            if res:
                take(res)
                return

    # 1. the names themselves
    for raw in names[:MAX_NAME_SEARCHES]:
        run(raw)
        if best() >= ALIAS_EXACT_SCORE:
            break

    # 2. looser searches (a hyphen or a long subtitle can make WeebCentral return nothing)
    if best() < MATCH_MIN:
        tried, n = {raw.lower() for raw in names[:MAX_NAME_SEARCHES]}, 0
        for raw in names[:3]:
            for q in _query_variants(raw):
                if q.lower() in tried or n >= MAX_LOOSE_SEARCHES:
                    continue
                tried.add(q.lower())
                n += 1
                run(q)
                if best() >= MATCH_MIN:
                    break
            if best() >= MATCH_MIN or n >= MAX_LOOSE_SEARCHES:
                break

    # 3. the other names WeebCentral lists for the best few results
    if best() < MATCH_MIN and found:
        pool = sorted((c for c in found.values() if c["score"] >= ALIAS_MIN_SCORE),
                      key=lambda c: c["score"], reverse=True)[:MAX_ALIAS_LOOKUPS]
        for c in pool:
            try:
                aliases = _wc_aliases(c["id"])
            except Exception as e:
                state["err"] = state["err"] or e
                continue
            a = max((_best_sim(name_forms, x) for x in aliases), default=0.0)
            if a >= ALIAS_EXACT_SCORE:
                a = ALIAS_EXACT_SCORE                  # a shared name is strong, not proof
            if a > c["score"]:
                found[c["id"]] = {**c, "score": round(min(a + (0.03 if year and c.get("year") == year else 0), 1.0), 3),
                                  "via": "alias"}

    if not found and state["err"]:
        raise state["err"]
    return sorted(found.values(), key=lambda c: c["score"], reverse=True)[:limit]


_match_lock = threading.Lock()


def _matches_load():
    try:
        with open(MATCH_FILE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _matches_save(data):
    tmp = MATCH_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, MATCH_FILE)


def _mkey(aid, provider):
    """The key of a match in anilist_matches.json. WeebCentral keeps the plain AniList id
    (so a file written before providers existed still works); MangaDex has its own key,
    so choosing a series on one site never replaces the pick on the other. Every other
    provider is "<id>@<provider>"."""
    return str(aid) if provider == "weebcentral" else f"{aid}@{provider}"


def match_set(aid, wc_id, title, manual, score):
    prov = provider_of(wc_id)
    with _match_lock:
        data = _matches_load()
        data[_mkey(aid, prov)] = {"id": wc_id, "title": title, "manual": bool(manual), "score": score}
        _matches_save(data)


def match_clear(aid, provider=None):
    with _match_lock:
        data = _matches_load()
        data.pop(_mkey(aid, provider or provider_get()), None)
        _matches_save(data)


def match_reverse(series):
    """The AniList id a series (WeebCentral or MangaDex) was matched to, or None."""
    sid = series_id(series)
    with _match_lock:
        data = _matches_load()
    for key, m in data.items():
        if series_id(m.get("id", "")) == sid:
            return key.split("@")[0]
    return None


def al_match(m, provider=None):
    """-> (match or None, candidates). A kept match wins; else the best name match."""
    prov = provider or provider_get()
    with _match_lock:
        kept = _matches_load().get(_mkey(m["id"], prov))
    if kept and kept.get("id"):
        return ({"id": kept["id"], "title": kept.get("title", ""),
                 "manual": bool(kept.get("manual")), "score": kept.get("score")}, [])

    cands = source_candidates(prov, m)
    if cands and cands[0]["score"] >= MATCH_MIN:
        best = cands[0]
        match_set(m["id"], best["id"], best["title"], False, best["score"])
        return ({"id": best["id"], "title": best["title"], "manual": False,
                 "score": best["score"]}, cands)
    # Leave a trace of why: what was searched and what came back (top three, with scores).
    top = ", ".join(f'{c["title"]!r} {c["score"]}' for c in cands[:3]) or "no results"
    print(f"[manga-server] no {PROVIDERS[prov]} match for {_al_name_variants(m)[:2]}: {top}", flush=True)
    return None, cands


def al_detail(aid, provider=None):
    m    = al_media(aid)
    out  = _al_base(m)
    prov = provider or provider_get()
    name = PROVIDERS[prov]
    try:
        match, cands = al_match(m, prov)
    except Exception as e:
        out.update(sourceError=f"Couldn't search {name}: {e}")
        return out
    if not match:
        out.update(unmatched=True)
        return out
    out["match"] = match
    out["id"]    = match["id"]
    try:
        wc = info(match["id"])
    except Exception as e:
        out["sourceError"] = f"Couldn't load the chapters from {name}: {e}"
        return out
    out["chapters"] = wc.get("chapters", [])
    if not out["description"]:
        out["description"] = wc.get("description", "")
    if not out["authors"]:
        out["authors"] = wc.get("authors", [])
    if not out["image"]:
        out["image"] = wc.get("image", "")
    return out


def info_for_ui(full_id):
    """/info for the panel: a series that was matched from AniList opens with the
    AniList details too (so the library shows the same page as browse does)."""
    aid = match_reverse(full_id)
    if aid:
        try:
            # the title opens with the site its series belongs to, whichever one is picked now
            return al_detail(aid, provider_of(full_id))
        except Exception:
            pass                                # AniList down: the plain page will do
    return info(full_id)


def al_candidates(aid, q):
    q = (q or "").strip()
    prov = provider_get()
    if prov != "weebcentral":
        if q:
            rows = md_search(q, 0, 20)["results"] if prov == "mangadex" else sw_search(q)["results"][:20]
            return {"results": rows}
        return {"results": source_candidates(prov, al_media(aid), 12)}
    if q:
        for attempt in [q, *_query_variants(q)[:3]]:
            res = search(attempt, None, 0, "Best Match")["results"]
            if res:
                return {"results": res[:20]}
        return {"results": []}
    return {"results": _wc_candidates(al_media(aid), 12)}


# ── Providers: which site the chapters come from ──────────────────────────
# AniList still does the finding. A provider only answers three things: which series
# is this title, what are its chapters, and where are the pages of a chapter.
# WeebCentral ids stay as they were; every MangaDex id starts with "md-" (the series
# and its chapters), so the library, favourites, downloads and read marks of the two
# sites never meet and nothing that was saved before has to change.

PROVIDERS     = {"weebcentral": "WeebCentral", "mangadex": "MangaDex", "suwayomi": "Suwayomi"}
PROVIDER_FILE = os.path.join(DATA_DIR, "provider.json")
MD_PREFIX     = "md-"
SW_PREFIX     = "sw-"
# Suwayomi is offered in the Source key only when it is set up (it needs a running server).
# "Set up" is either SEKAIPOP_SW_CMD / SEKAIPOP_SW_URL, or the launcher that install-deps.sh writes
# next to the jar it downloads (~/.local/share/suwayomi/run.sh), so a plain install needs no env var.
SW_LAUNCHER   = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                             "suwayomi", "run.sh")
SW_ENABLED    = bool(os.environ.get("SEKAIPOP_SW_CMD") or os.environ.get("SEKAIPOP_SW_URL")
                     or os.access(SW_LAUNCHER, os.X_OK))

_prov_lock = threading.Lock()
_prov      = {"v": None}


def is_md(some_id):
    return str(some_id or "").startswith(MD_PREFIX)


def is_sw(some_id):
    return str(some_id or "").startswith(SW_PREFIX)


def provider_of(some_id):
    """Which provider an id belongs to: its prefix says (WeebCentral ids have none)."""
    if is_md(some_id):
        return "mangadex"
    if is_sw(some_id):
        return "suwayomi"
    return "weebcentral"


def _providers():
    return {k: v for k, v in PROVIDERS.items() if k != "suwayomi" or SW_ENABLED}


def source_candidates(prov, m, limit=8):
    if prov == "mangadex":
        return md_candidates(m, limit)
    if prov == "suwayomi":
        return sw_candidates(m, limit)
    return _wc_candidates(m, limit)


def source_latest(page=1):
    """The picked provider's own "latest" list."""
    prov = provider_get()
    if prov == "mangadex":
        return md_latest(page)
    if prov == "suwayomi":
        return sw_latest(page)
    return latest_updates(page)


BROWSE_SORTS = ("popular", "latest", "rating", "views")


def source_browse(sort="popular", page=1):
    """The picked provider's own catalog in one order, the way Mihon browses a source: Popular and
    Latest are the source's two feeds, and Highest rated / Most viewed are used only when the source
    can sort that way (the answer's \"sorts\" lists what it offers). Nothing here asks AniList.
    Raises ValueError for a sort this source does not have."""
    sort = sort if sort in BROWSE_SORTS else "popular"
    page = max(1, int(page))
    prov = provider_get()
    if prov == "mangadex":
        return md_browse(sort, page)
    if prov == "suwayomi":
        return sw_browse(sort, page)
    return wc_browse(sort, page)


def wc_browse(sort, page):
    """WeebCentral: Popular is its own search ordered by popularity, Latest its latest-updates page.
    It has no rating or view count to sort by."""
    sorts = ["popular", "latest"]
    if sort == "latest":
        out = dict(latest_updates(page))
    elif sort == "popular":
        d = search("", None, (page - 1) * PAGE_LIMIT, "Popularity")
        out = {"results": d["results"], "hasMore": d["hasMore"], "nextPage": page + 1}
    else:
        raise ValueError(f"WeebCentral cannot sort by {sort}")
    out["sorts"] = sorts
    return out


def provider_get():
    with _prov_lock:
        if _prov["v"] is None:
            try:
                with open(PROVIDER_FILE) as f:
                    v = (json.load(f) or {}).get("provider")
            except (OSError, ValueError, AttributeError):
                v = None
            _prov["v"] = v if v in _providers() else "weebcentral"
        return _prov["v"]


def provider_status():
    cur = provider_get()
    return {"provider": cur, "label": PROVIDERS[cur],
            "providers": [{"id": k, "label": v} for k, v in _providers().items()]}


def provider_set(name):
    if name not in _providers():
        raise ValueError(f"unknown provider {name!r}")
    tmp = PROVIDER_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"provider": name}, f)
    os.replace(tmp, PROVIDER_FILE)
    with _prov_lock:
        _prov["v"] = name
    return provider_status()


# ── MangaDex ───────────────────────────────────────────────────────────────
# MangaDex has a real JSON API (https://api.mangadex.org/docs/), so none of this is
# scraping: a few small requests, no HTML. It asks for about 5 requests a second, so
# every call goes through one small gate, and a 429 is waited out once.
# Pages come from MangaDex@Home servers: /at-home/server/<chapter> gives a server and a
# short-lived token, and the image links are built from them. Those links go stale while a
# long chapter is read, so the panel is never given them: it gets /mdpage?c=&i= links of
# this server, and a page is fetched (with a fresh server if the old one failed) when asked.

MD_API      = "https://api.mangadex.org"
MD_COVERS   = "https://uploads.mangadex.org/covers"
MD_LANG     = os.environ.get("SEKAIPOP_MD_LANG", "en")
# "data" is the original quality; "data-saver" is smaller and faster on a slow line
MD_QUALITY  = "data-saver" if os.environ.get("SEKAIPOP_MD_QUALITY") == "data-saver" else "data"
MD_RATINGS  = ("safe", "suggestive", "erotica", "pornographic")
MD_UA       = "SekaiPop-MangaReader/1.0 (personal desktop reader)"
MD_MIN_GAP  = 0.25
MD_MAX_FEED = 20            # feed pages of 500 chapters: a bad reply cannot loop for ever
TTL_MD_HOME = 600           # an at-home answer (its token is short-lived)

_md_gate = threading.Lock()
_md_last = [0.0]


def _md_wait():
    with _md_gate:
        gap = MD_MIN_GAP - (time.monotonic() - _md_last[0])
        if gap > 0:
            time.sleep(gap)
        _md_last[0] = time.monotonic()


def _retry_after(headers):
    """Seconds to wait after a 429. MangaDex may send seconds or a unix time: both are read."""
    try:
        v = float(headers.get("Retry-After") or headers.get("X-RateLimit-Retry-After") or 1)
    except (TypeError, ValueError):
        v = 1.0
    if v > 1_000_000_000:
        v -= time.time()
    return min(max(v, 0.5), 5.0)


def md_get(path, params=None, timeout=20):
    """GET api.mangadex.org<path>?params -> parsed JSON. params is a list of (key, value)."""
    url = MD_API + path
    if params:
        url += "?" + urlencode(params, doseq=True)
    headers = {"User-Agent": MD_UA, "Accept": "application/json"}
    for attempt in (0, 1):
        _md_wait()
        r = _get(url, headers, timeout)
        if r.status_code == 429 and attempt == 0:
            time.sleep(_retry_after(r.headers))
            continue
        r.raise_for_status()
        return r.json()


def _md_ratings():
    return [("contentRating[]", c) for c in MD_RATINGS]


def _md_pick(d):
    """A {language: text} map -> the English text, else the first one."""
    if not isinstance(d, dict):
        return ""
    return d.get(MD_LANG) or d.get("en") or next((v for v in d.values() if v), "")


def _md_titles(m):
    """-> (main title, every other name MangaDex has for the series)."""
    a = m.get("attributes") or {}
    t = a.get("title") or {}
    main = _md_pick(t)
    others = [v for v in t.values() if v and v != main]
    for d in a.get("altTitles") or []:
        others.extend(v for v in d.values() if v)
    return main, others


def _md_cover(m):
    for rel in m.get("relationships") or []:
        if rel.get("type") == "cover_art":
            fn = (rel.get("attributes") or {}).get("fileName")
            if fn:
                return f"{MD_COVERS}/{m['id']}/{fn}.512.jpg"
    return ""


def _md_row(m):
    a = m.get("attributes") or {}
    title, others = _md_titles(m)
    cover = _md_cover(m)
    return {
        "id":        MD_PREFIX + m["id"],
        "title":     title,
        "image":     proxy_url(cover) if cover else "",
        "status":    (a.get("status") or "").replace("_", " ").capitalize(),
        "year":      str(a.get("year") or ""),
        "type":      "",
        "tags":      [_md_pick((t.get("attributes") or {}).get("name"))
                      for t in (a.get("tags") or [])][:6],
        "altTitles": others,
        "al":        str((a.get("links") or {}).get("al") or ""),   # MangaDex knows its AniList id
        "updatedAt": a.get("updatedAt") or "",
    }


def md_search(query, offset=0, limit=20):
    params = [("title", query), ("limit", limit), ("offset", offset),
              ("includes[]", "cover_art"), ("availableTranslatedLanguage[]", MD_LANG),
              ("order[relevance]", "desc")] + _md_ratings()
    d = md_get("/manga", params)
    rows = [_md_row(m) for m in d.get("data") or []]
    return {"results": rows, "hasMore": offset + len(rows) < (d.get("total") or 0),
            "nextOffset": offset + len(rows)}


def md_latest(page=1):
    return _cached(f"mdlatest:{page}", TTL_LATEST, lambda: _md_latest(page))


def _md_latest(page):
    return _md_listing("latestUploadedChapter", page)


# MangaDex can order its catalog by follows (Popular), newest chapter (Latest) and rating. It has
# no view count to order by, so Most viewed is not offered there.
MD_ORDER = {"popular": "followedCount", "rating": "rating"}
MD_SORTS = ("popular", "latest", "rating")


def md_browse(sort, page):
    if sort == "latest":
        out = dict(md_latest(page))
    elif sort in MD_ORDER:
        out = _cached(f"mdbrowse:{sort}:{page}", TTL_LATEST, lambda: _md_listing(MD_ORDER[sort], page))
        out = dict(out)
    else:
        raise ValueError(f"MangaDex cannot sort by {sort}")
    out["sorts"] = list(MD_SORTS)
    return out


def _md_listing(order_key, page):
    offset = (max(1, page) - 1) * PAGE_LIMIT
    params = [("limit", PAGE_LIMIT), ("offset", offset),
              (f"order[{order_key}]", "desc"),
              ("includes[]", "cover_art"), ("availableTranslatedLanguage[]", MD_LANG)] + _md_ratings()
    d = md_get("/manga", params)
    rows = []
    for m in d.get("data") or []:
        r = _md_row(m)
        rows.append({"id": r["id"], "title": r["title"], "image": r["image"], "status": "",
                     "type": "", "chapter": "", "updatedAt": r["updatedAt"]})
    return {"results": rows, "hasMore": offset + len(rows) < (d.get("total") or 0),
            "nextPage": page + 1}


def md_candidates(m, limit=8):
    """MangaDex series that could be this AniList title, best first, each with a score.
    MangaDex lists the AniList id of many series: that is an exact match (score 1.0)."""
    aid        = str(m["id"])
    names      = _al_name_variants(m)
    name_forms = [_forms(n) for n in names]
    year       = str((m.get("startDate") or {}).get("year") or "")
    found, state = {}, {"err": None}

    def best():
        return max((c["score"] for c in found.values()), default=0.0)

    def take(rows):
        for r in rows:
            if r["al"] and r["al"] == aid:
                s, via = 1.0, "anilist"
            else:
                s = _best_sim(name_forms, r["title"])
                alt = max((_best_sim(name_forms, x) for x in r["altTitles"]), default=0.0)
                s, via = (max(s, min(alt, ALIAS_EXACT_SCORE)), "alias") if alt > s else (s, "")
                if year and r["year"] == year:
                    s += 0.03
            s = round(min(s, 1.0), 3)
            if r["id"] not in found or s > found[r["id"]]["score"]:
                found[r["id"]] = {**r, "score": s, **({"via": via} if via else {})}

    def run(q):
        try:
            take(md_search(q, 0, 10)["results"])
        except Exception as e:
            state["err"] = e

    for raw in names[:MAX_NAME_SEARCHES]:
        run(raw)
        if best() >= ALIAS_EXACT_SCORE:
            break
    if best() < MATCH_MIN:
        tried, n = {raw.lower() for raw in names[:MAX_NAME_SEARCHES]}, 0
        for raw in names[:3]:
            for q in _query_variants(raw):
                if q.lower() in tried or n >= MAX_LOOSE_SEARCHES:
                    continue
                tried.add(q.lower())
                n += 1
                run(q)
                if best() >= MATCH_MIN:
                    break
            if best() >= MATCH_MIN or n >= MAX_LOOSE_SEARCHES:
                break

    if not found and state["err"]:
        raise state["err"]
    return sorted(found.values(), key=lambda c: c["score"], reverse=True)[:limit]


def _md_description(raw):
    """MangaDex descriptions are markdown with the translator's notes after a --- line."""
    text = re.split(r"\n\s*(?:---|\*\*\*|___)\s*\n", raw or "", maxsplit=1)[0]
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    return re.sub(r"[*_`#>]+", "", text).strip()


def _md_chapters(mid):
    rows, offset = [], 0
    for _ in range(MD_MAX_FEED):
        d = md_get(f"/manga/{mid}/feed", [
            ("limit", 500), ("offset", offset), ("translatedLanguage[]", MD_LANG),
            ("order[chapter]", "asc"),
            ("includeExternalUrl", 0), ("includeEmptyPages", 0), ("includeFuturePublishAt", 0),
        ] + _md_ratings())
        data = d.get("data") or []
        rows.extend(data)
        offset += len(data)
        if not data or offset >= (d.get("total") or 0):
            break
    return _md_dedupe(rows)


def _md_dedupe(rows):
    """Several groups often upload the same chapter. Keep one per chapter number: the one
    with the most pages (a half chapter loses), the earliest of those."""
    best = {}
    for r in rows:
        a = r.get("attributes") or {}
        pages = a.get("pages") or 0
        if a.get("externalUrl") or pages <= 0:
            continue                                   # an official link, or nothing to read
        num = str(a.get("chapter") or "").strip()
        key = num if num else "x:" + (a.get("title") or r["id"])
        when = a.get("publishAt") or a.get("readableAt") or ""
        cur = best.get(key)
        if cur is None or pages > cur["pages"] or (pages == cur["pages"] and when < cur["when"]):
            best[key] = {"r": r, "pages": pages, "when": when, "num": num}
    out = []
    for v in best.values():
        a, num = v["r"]["attributes"], v["num"]
        title = (a.get("title") or "").strip()
        out.append({
            "id":        MD_PREFIX + v["r"]["id"],
            "title":     title or (f"Chapter {num}" if num else "Oneshot"),
            "chapter":   num or title or "Oneshot",
            "kind":      "chapter" if num else "extra",
            "publishAt": v["when"],
        })
    # numbered chapters in order, then the extras by date: the site's order, oldest first
    out.sort(key=lambda c: (0, chapter_sort_num(c["chapter"]), c["publishAt"]) if c["kind"] == "chapter"
            else (1, 0.0, c["publishAt"]))
    for i, c in enumerate(out):
        c["index"] = i
    return out


def md_info(full_id):
    mid = full_id[len(MD_PREFIX):]
    d = md_get(f"/manga/{mid}", [("includes[]", "cover_art"), ("includes[]", "author"),
                                 ("includes[]", "artist")])
    m = d.get("data") or {}
    a = m.get("attributes") or {}
    title, _ = _md_titles(m)
    authors = []
    for rel in m.get("relationships") or []:
        if rel.get("type") in ("author", "artist"):
            n = ((rel.get("attributes") or {}).get("name") or "").strip()
            if n and n not in authors:
                authors.append(n)
    cover = _md_cover(m)
    return {
        "id":          full_id,
        "title":       title,
        "description": _md_description(_md_pick(a.get("description"))),
        "status":      (a.get("status") or "").replace("_", " ").capitalize(),
        "image":       proxy_url(cover) if cover else "",
        "authors":     authors,
        "chapters":    _md_chapters(mid),
    }


def _md_home(chapter_id):
    cid = chapter_id[len(MD_PREFIX):]
    return _cached(f"mdhome:{cid}", TTL_MD_HOME, lambda: md_get(f"/at-home/server/{cid}"))


def md_pages(chapter_id):
    ch = _md_home(chapter_id).get("chapter") or {}
    n  = len(ch.get("dataSaver" if MD_QUALITY == "data-saver" else "data") or [])
    return [{"page": i + 1,
             "img": f"http://127.0.0.1:{PORT}/mdpage?c={quote(chapter_id, safe='')}&i={i}"}
            for i in range(n)]


def _md_report(url, ok, nbytes, started):
    """MangaDex asks readers to say how an image server did (best effort, never fatal)."""
    if ".mangadex.network" not in url:
        return

    def go():
        try:
            _post_json("https://api.mangadex.network/report",
                       {"url": url, "success": ok, "bytes": nbytes,
                        "duration": int((time.monotonic() - started) * 1000), "cached": False},
                       {"User-Agent": MD_UA}, 10)
        except Exception:
            pass
    threading.Thread(target=go, daemon=True).start()


def md_page_bytes(chapter_id, index):
    """The bytes and content type of page `index` (from 0). A page seen before is served from
    the image cache; if the image server fails, a fresh one is asked for once."""
    key = f"md:{chapter_id}:{index}:{MD_QUALITY}"
    cached = _img_get(key)
    if cached:
        return cached
    for attempt in (0, 1):
        ch = _md_home(chapter_id)
        files = (ch.get("chapter") or {}).get("dataSaver" if MD_QUALITY == "data-saver" else "data") or []
        if index >= len(files):
            raise IndexError(f"page {index + 1} of {len(files)}")
        url = f"{ch['baseUrl']}/{MD_QUALITY}/{ch['chapter']['hash']}/{files[index]}"
        started = time.monotonic()
        try:
            body, ctype = _raw_get(url)
        except Exception:
            _md_report(url, False, 0, started)
            _cache_drop(f"mdhome:{chapter_id[len(MD_PREFIX):]}")      # ask for another server
            if attempt:
                raise
            continue
        _md_report(url, True, len(body), started)
        _img_put(key, body, ctype)
        return body, ctype


# ── Suwayomi ───────────────────────────────────────────────────────────────
# Suwayomi (https://github.com/Suwayomi/Suwayomi-Server) is a local server that runs Mihon /
# Tachiyomi extensions and exposes them over GraphQL at <SW_URL>/api/graphql. It already knows how
# to read hundreds of sites, so this block is the same five answers the MangaDex block gives
# (search, latest, candidates, info, pages) asked of Suwayomi instead of a site.
#
# Three things differ from MangaDex:
#   * Suwayomi is a process. If SEKAIPOP_SW_CMD is set it is started on first use and stopped when
#     this server exits. Its first start (a JVM) takes a few seconds; later calls are quick.
#   * It has many sources (one per extension). A search or the latest list asks several of them at
#     once and interleaves the answers. Each row's "type" says which source it came from.
#   * Ids are Suwayomi's own database ids: "sw-<manga id>" for a series, "sw-<chapter id>" for a
#     chapter. Page links go through /swpage like MangaDex's through /mdpage, so the panel never
#     holds a link that goes stale and every page lands in the image cache.
# Not supported: Suwayomi's login (auth mode). Leave it off; it listens on 127.0.0.1 only.

SW_URL         = os.environ.get("SEKAIPOP_SW_URL", "http://127.0.0.1:4567").rstrip("/")
SW_CMD         = os.environ.get("SEKAIPOP_SW_CMD", "")      # e.g. "java -jar ~/.local/share/suwayomi/Suwayomi-Server.jar"
if not SW_CMD and not os.environ.get("SEKAIPOP_SW_URL") and os.access(SW_LAUNCHER, os.X_OK):
    SW_CMD = "'" + SW_LAUNCHER.replace("'", "'\\''") + "'"       # run through sh, so quote the path
SW_LANG        = os.environ.get("SEKAIPOP_SW_LANG", "en")
# Source ids, comma separated; empty = every installed source in SW_LANG. When set, the order is
# also a preference: of two equal matches the earlier source wins.
SW_SOURCES     = [s.strip() for s in os.environ.get("SEKAIPOP_SW_SOURCES", "").split(",") if s.strip()]
SW_NSFW        = os.environ.get("SEKAIPOP_SW_NSFW") == "1"  # include sources Suwayomi marks as NSFW
SW_MAX_SOURCES = 8          # when SW_SOURCES is empty: more than this many sources are cut to the first ones
SW_WORKERS     = 6          # sources asked at the same time
SW_LOG         = os.path.join(DATA_DIR, "suwayomi.log")
SW_UA          = "SekaiPop-MangaReader/1.0 (personal desktop reader)"
TTL_SW_PAGES   = 600
SW_PAGE_STEP   = 20         # /search?offset=<n> counts in steps of this: offset 40 is page 3

_sw_proc     = None
_sw_lock     = threading.Lock()
_sw_ok_until = [0.0]        # "Suwayomi answered a moment ago": saves a probe on every call


# ── Lifecycle: start Suwayomi when it is needed, stop it when this server exits ──

def _sw_up():
    """True when anything answers at SW_URL (even an error page: it is running)."""
    try:
        return _get(SW_URL + "/api/graphql", {"User-Agent": SW_UA}, 2).status_code < 500
    except Exception:
        return False


def sw_ensure_up(wait=60):
    """Make sure Suwayomi answers; start it first if SEKAIPOP_SW_CMD says how."""
    global _sw_proc
    with _sw_lock:                                   # one thread starts it, the others wait here
        if time.monotonic() < _sw_ok_until[0]:
            return
        if not _sw_up():
            if not SW_CMD:
                raise RuntimeError(f"Suwayomi is not running at {SW_URL} "
                                   "(set SEKAIPOP_SW_CMD to start it automatically)")
            if _sw_proc is None or _sw_proc.poll() is not None:
                with open(SW_LOG, "ab") as log:      # its output goes to a file, not nowhere
                    _sw_proc = subprocess.Popen(
                        SW_CMD, shell=True, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                        start_new_session=True)      # its own process group, so sw_stop can end all of it
            deadline = time.monotonic() + wait
            while not _sw_up():
                code = _sw_proc.poll()
                # exit code 0 is fine: a launcher such as `systemctl --user start x` returns at once
                if code not in (None, 0):
                    raise RuntimeError(f"Suwayomi exited with code {code} (see {SW_LOG})")
                if time.monotonic() > deadline:
                    raise RuntimeError(f"Suwayomi did not start in {wait} s (see {SW_LOG})")
                time.sleep(0.5)
        _sw_ok_until[0] = time.monotonic() + 15


def sw_stop():
    """End the Suwayomi this server started (never one that was already running)."""
    p = _sw_proc
    if not p or p.poll() is not None:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)                    # the whole group: with shell=True, p is only `sh`
        except OSError:
            return
        try:
            p.wait(5)
            return
        except subprocess.TimeoutExpired:
            continue


atexit.register(sw_stop)


# ── GraphQL transport ──

def sw_gql(query, variables=None, timeout=60):
    sw_ensure_up()
    try:
        r = _post_json(SW_URL + "/api/graphql", {"query": query, "variables": variables or {}},
                       {"User-Agent": SW_UA, "Accept": "application/json"}, timeout)
        r.raise_for_status()
        d = r.json()
    except Exception:
        _sw_ok_until[0] = 0.0                        # it may have died: check again next time
        raise
    if d.get("errors"):
        raise RuntimeError(d["errors"][0].get("message") or "Suwayomi GraphQL error")
    return d["data"]


# These field names come from Suwayomi's schema as I know it; open <SW_URL>/api/graphql (GraphiQL)
# and run each one once if a Suwayomi update ever changes an answer.
Q_SOURCES = "query { sources { nodes { id name lang supportsLatest isNsfw } } }"

M_SOURCE_MANGA = """mutation($input: FetchSourceMangaInput!) {
  fetchSourceManga(input: $input) {
    hasNextPage
    mangas { id title thumbnailUrl status genre description author artist }
  }
}"""
M_MANGA    = "mutation($id: Int!) { fetchManga(input: {id: $id}) { manga { id title thumbnailUrl status genre description author artist } } }"
M_CHAPTERS = "mutation($id: Int!) { fetchChapters(input: {mangaId: $id}) { chapters { id name chapterNumber scanlator uploadDate sourceOrder } } }"
M_PAGES    = "mutation($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }"


def _sw_all_sources():
    """Every source Suwayomi has installed, whatever its language (not cached)."""
    return sw_gql(Q_SOURCES)["sources"]["nodes"]


def _sw_sources():
    def load():
        every = _sw_all_sources()
        picked = sw_choice_get()
        if picked is not None:                       # the Sources page's pick: exactly these, in this order
            by_id = {str(n["id"]): n for n in every}
            nodes = [by_id[i] for i in picked if i in by_id]
            if nodes:
                return nodes
            print("[manga-server] suwayomi: none of the picked sources is installed any more; "
                  "using the automatic choice", flush=True)
        nodes = [n for n in every if n["lang"] in (SW_LANG, "all") and (SW_NSFW or not n.get("isNsfw"))]
        if SW_SOURCES:
            nodes = [n for n in nodes if str(n["id"]) in SW_SOURCES]
            nodes.sort(key=lambda n: SW_SOURCES.index(str(n["id"])))      # your order = your preference
        else:
            nodes.sort(key=lambda n: n["name"].lower())
        if not nodes:
            raise RuntimeError(f"Suwayomi has no {SW_LANG!r} source: open Sources in the manga panel "
                               "(the puzzle key beside the Source key in Browse) and install an extension")
        if not SW_SOURCES and len(nodes) > SW_MAX_SOURCES:
            print(f"[manga-server] suwayomi: {len(nodes)} sources, using the first {SW_MAX_SOURCES} "
                  "(pick them in the panel's Sources page)", flush=True)
            nodes = nodes[:SW_MAX_SOURCES]
        return nodes
    return _cached("sw:sources", 600, load)


def _sw_thumb(path):
    if not path:
        return ""
    return proxy_url(SW_URL + path if path.startswith("/") else path)


def _sw_status(s):
    return (s or "").replace("_", " ").capitalize()


def _sw_iso(ms):
    """Suwayomi dates are milliseconds since 1970 (as a string); 0 means unknown."""
    try:
        v = int(ms)
    except (TypeError, ValueError):
        return ""
    return datetime.fromtimestamp(v / 1000, timezone.utc).isoformat() if v > 0 else ""


def _sw_ask_sources():
    """The sources a search or a Latest list asks: the focused one when the panel picked one of
    the sources, else every picked source. A focus that is no longer picked is ignored."""
    srcs = _sw_sources()
    fid = _sw_focus["id"]
    if fid:
        one = [s for s in srcs if str(s["id"]) == fid]
        if one:
            return one
    return srcs


def _sw_row(m, source=""):
    return {"id": SW_PREFIX + str(m["id"]), "title": m["title"], "image": _sw_thumb(m.get("thumbnailUrl")),
            "status": _sw_status(m.get("status")), "year": "",
            "type": source,                          # the card's label: which source this came from
            "tags": (m.get("genre") or [])[:6], "altTitles": [], "al": "", "updatedAt": ""}


def _interleave(groups):
    """One from each list in turn, so no source fills the whole first screen."""
    out = []
    for i in range(max((len(g) for g in groups), default=0)):
        out.extend(g[i] for g in groups if i < len(g))
    return out


# ── The same five things the MangaDex block answers ──

def _sw_fan_out(kind, page, query="", sort=None):
    """Ask every chosen source in parallel -> (interleaved rows, any source has a next page).
    sort "rating" / "views" is a search with no words and that source's own sort filter switched on
    (what Mihon does: sorting lives in the source's filters); only sources that have one are asked."""
    srcs = _sw_ask_sources()
    changes = {}
    if kind == "LATEST":
        srcs = [s for s in srcs if s.get("supportsLatest")]
    if sort in ("rating", "views"):
        kind, query, able = "SEARCH", "", []
        for s in srcs:
            ch = _sw_sorts_of(s).get(sort)
            if ch:
                able.append(s)
                changes[str(s["id"])] = ch
        if not able:
            raise ValueError(f"none of the picked sources can sort by {sort}")
        srcs = able

    def one(s):
        inp = {"source": s["id"], "type": kind, "page": page}
        if kind == "SEARCH":
            inp["query"] = query
        if str(s["id"]) in changes:
            inp["filters"] = [changes[str(s["id"])]]
        try:
            d = sw_gql(M_SOURCE_MANGA, {"input": inp})["fetchSourceManga"]
            return [_sw_row(m, s["name"]) for m in d["mangas"]], bool(d.get("hasNextPage")), None
        except Exception as e:
            print(f"[manga-server] suwayomi source {s['name']}: {e}", flush=True)
            return [], False, e

    with ThreadPoolExecutor(max_workers=min(SW_WORKERS, max(1, len(srcs)))) as ex:
        res = list(ex.map(one, srcs))
    if res and all(r[2] for r in res):               # every source failed: say so, do not pretend "no results"
        raise res[0][2]
    return _interleave([r[0] for r in res]), any(r[1] for r in res)


def sw_search(query, offset=0):
    rows, more = _sw_fan_out("SEARCH", offset // SW_PAGE_STEP + 1, query)
    return {"results": rows, "hasMore": more, "nextOffset": offset + SW_PAGE_STEP}


def sw_latest(page=1):
    return _cached(f"swlatest:{_sw_focus['id']}:{page}", TTL_LATEST, lambda: _sw_latest(page))


def _sw_latest(page):
    rows, more = _sw_fan_out("LATEST", page)
    return {"results": [{"id": r["id"], "title": r["title"], "image": r["image"], "status": "",
                         "type": r["type"], "chapter": "", "updatedAt": ""} for r in rows],
            "hasMore": more, "nextPage": page + 1}


# ── Browse: Popular / Latest feeds and the sorts a source's own filters offer ──
# Every Mihon source has a Popular feed; most have Latest (supportsLatest). Highest rated and Most
# viewed are not feeds: a source that has them lists them as values of a Sort filter (or an "Order by"
# select), so each source's filters are read once, the values that look like a rating or a view count
# are found by name, and sorting means a search with those filters set. A source whose filters do not
# say simply is not offered those two.

SW_SORT_WORDS = {
    "views":  re.compile(r"view|\bhits?\b|most read", re.I),
    "rating": re.compile(r"rating|rated|score", re.I),
}
SW_SORT_SKIP = re.compile(r"a-z|z-a|alpha|title", re.I)


def _sw_sorts_of(source):
    """-> {"rating": change, "views": change} for one source: each change is the FilterChangeInput
    that turns that sort on (descending). Empty when the source has no such sort or Suwayomi will not
    say. A failed ask is not kept, so the next call tries again."""
    sid = str(source["id"])
    if not SW_SOURCE_ID.match(sid):
        return {}

    def load():
        frags = []
        for t in ("SortFilter", "SelectFilter"):
            f = _sw_fields(t)
            if f and {"name", "values"} <= f:
                frags.append(f"... on {t} {{ name values }}")
        if not frags:
            return {}
        d = sw_gql('query { source(id: "%s") { filters { __typename %s } } }' % (sid, " ".join(frags)))
        nodes = ((d or {}).get("source") or {}).get("filters") or []
        out = {}
        for pos, f in enumerate(nodes):                  # the filter's place in the list is its position
            kind = f.get("__typename")
            if kind not in ("SortFilter", "SelectFilter"):
                continue
            for sort, rx in SW_SORT_WORDS.items():
                if sort in out:
                    continue
                for idx, v in enumerate(f.get("values") or []):
                    if rx.search(str(v)) and not SW_SORT_SKIP.search(str(v)):
                        out[sort] = ({"position": pos, "sortState": {"index": idx, "ascending": False}}
                                     if kind == "SortFilter" else {"position": pos, "selectState": idx})
                        break
        return out

    try:
        return _cached(f"sw:sorts:{sid}", 600, load)
    except Exception as e:
        print(f"[manga-server] suwayomi source {source.get('name')}: sorts: {e}", flush=True)
        return {}


def _sw_sorts_offered():
    """The sorts the asked sources give: Popular always, Latest when one has it, rating / views when
    one has that sort. With one source picked (the panel's usual state) this is exactly that source."""
    srcs = _sw_ask_sources()
    out = ["popular"]
    if any(s.get("supportsLatest") for s in srcs):
        out.append("latest")
    for sort in ("rating", "views"):
        if any(_sw_sorts_of(s).get(sort) for s in srcs):
            out.append(sort)
    return out


def sw_browse(sort, page):
    return _cached(f"swbrowse:{_sw_focus['id']}:{sort}:{page}", TTL_LATEST, lambda: _sw_browse(sort, page))


def _sw_browse(sort, page):
    kind = {"popular": "POPULAR", "latest": "LATEST"}.get(sort, "SEARCH")
    rows, more = _sw_fan_out(kind, page, sort=sort)
    return {"results": [{"id": r["id"], "title": r["title"], "image": r["image"], "status": r["status"],
                         "type": r["type"], "chapter": "", "updatedAt": ""} for r in rows],
            "hasMore": more, "nextPage": page + 1, "sorts": _sw_sorts_offered()}


def sw_candidates(m, limit=8):
    """Which Suwayomi series could be this AniList title, best first, each with a score.
    Suwayomi has no AniList link like MangaDex's, so this is names only, scored the same way."""
    names      = _al_name_variants(m)
    name_forms = [_forms(n) for n in names]
    found, state = {}, {"err": None}

    def best():
        return max((c["score"] for c in found.values()), default=0.0)

    def run(q):
        try:
            for r in sw_search(q)["results"]:
                s = round(min(_best_sim(name_forms, r["title"]), 1.0), 3)
                if r["id"] not in found or s > found[r["id"]]["score"]:
                    found[r["id"]] = {**r, "score": s}
        except Exception as e:
            state["err"] = e

    for raw in names[:MAX_NAME_SEARCHES]:
        run(raw)
        if best() >= ALIAS_EXACT_SCORE:
            break
    if best() < MATCH_MIN:                           # a few looser spellings; each one asks every source
        tried, n = {raw.lower() for raw in names[:MAX_NAME_SEARCHES]}, 0
        for raw in names[:2]:
            for q in _query_variants(raw):
                if q.lower() in tried or n >= 3:
                    continue
                tried.add(q.lower())
                n += 1
                run(q)
                if best() >= MATCH_MIN:
                    break
            if best() >= MATCH_MIN or n >= 3:
                break
    if not found and state["err"]:
        raise state["err"]
    return sorted(found.values(), key=lambda c: c["score"], reverse=True)[:limit]


def _sw_chapters(mid):
    chs = sw_gql(M_CHAPTERS, {"id": mid})["fetchChapters"]["chapters"]
    chs.sort(key=lambda c: c.get("sourceOrder") or 0)
    best = {}
    for c in chs:                                    # one per number (a few sources list each group's upload)
        n = c.get("chapterNumber")
        key = f"{n:g}" if n is not None and n >= 0 else "x:" + (c.get("name") or str(c["id"]))
        best.setdefault(key, c)
    out = []
    for c in best.values():
        n = c.get("chapterNumber")
        label = f"{n:g}" if n is not None and n >= 0 else ""    # Suwayomi uses -1 for "no number"
        name = (c.get("name") or "").strip()
        out.append({"id": SW_PREFIX + str(c["id"]),
                    "title": name or (f"Chapter {label}" if label else "Oneshot"),
                    "chapter": label or name or "Oneshot",
                    "kind": "chapter" if label else "extra",
                    "publishAt": _sw_iso(c.get("uploadDate"))})
    out.sort(key=lambda c: (0, chapter_sort_num(c["chapter"]), c["publishAt"]) if c["kind"] == "chapter"
             else (1, 0.0, c["publishAt"]))
    for i, c in enumerate(out):
        c["index"] = i
    return out


def sw_info(full_id):
    mid = int(full_id[len(SW_PREFIX):])
    with ThreadPoolExecutor(max_workers=2) as ex:    # both go to the source site: ask together
        f_manga = ex.submit(sw_gql, M_MANGA, {"id": mid})
        f_chaps = ex.submit(_sw_chapters, mid)
        m, chapters = f_manga.result()["fetchManga"]["manga"], f_chaps.result()
    authors = []
    for field in ("author", "artist"):
        for n in re.split(r"\s*,\s*", m.get(field) or ""):
            if n and n not in authors:
                authors.append(n)
    return {"id": full_id, "title": m["title"], "description": (m.get("description") or "").strip(),
            "status": _sw_status(m.get("status")), "image": _sw_thumb(m.get("thumbnailUrl")),
            "authors": authors, "chapters": chapters}      # info() above this already caches for TTL_INFO


def _sw_page_paths(chapter_id):
    cid = int(chapter_id[len(SW_PREFIX):])
    return _cached(f"swpages:{cid}", TTL_SW_PAGES,
                   lambda: sw_gql(M_PAGES, {"id": cid})["fetchChapterPages"]["pages"])


def sw_pages(chapter_id):
    n = len(_sw_page_paths(chapter_id))
    return [{"page": i + 1, "img": f"http://127.0.0.1:{PORT}/swpage?c={quote(chapter_id, safe='')}&i={i}"}
            for i in range(n)]


def sw_page_bytes(chapter_id, index):
    """The bytes and content type of page `index` (from 0): from the image cache, else from
    Suwayomi, which gets the picture from the site (with that site's headers) and keeps its own copy."""
    key = f"sw:{chapter_id}:{index}"
    cached = _img_get(key)
    if cached:
        return cached
    paths = _sw_page_paths(chapter_id)
    if index >= len(paths):
        raise IndexError(f"page {index + 1} of {len(paths)}")
    p = paths[index]
    body, ctype = _raw_get(p if p.startswith("http") else SW_URL + p, timeout=60)
    _img_put(key, body, ctype)
    return body, ctype


def page_bytes(chapter_id, index):
    """One page of a MangaDex or Suwayomi chapter (the sources whose pages go through this server)."""
    return md_page_bytes(chapter_id, index) if is_md(chapter_id) else sw_page_bytes(chapter_id, index)


# ── Suwayomi management: repositories, extensions and the sources Browse asks ─
# What Suwayomi's own web page does for this reader's sake, so nobody has to open it:
#   * repositories: the list of extension indexes (Suwayomi setting "extensionRepos")
#   * extensions:   list, refresh from the repositories, install, update, uninstall
#   * sources:      which of the installed sources Browse and Latest ask (a pick kept in
#                   sw_sources.json beside provider.json; no pick = the automatic choice above)
# Schema differences between Suwayomi versions are read from GraphQL introspection (which fields an
# extension has, whether setSettings wraps its input in "settings"), and a wrong guess is retried the
# other way, so a Suwayomi update should not need a change here.

SW_SUGGESTED_REPOS = [
    {"name": "Keiyoushi", "url": "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"},
]
SW_EXT_BASE   = ["pkgName", "name", "lang", "versionName", "isInstalled", "hasUpdate", "isObsolete", "isNsfw", "iconUrl"]
SW_EXT_WANT   = SW_EXT_BASE + ["repo"]
SW_EXT_PKG_RE = re.compile(r"^[A-Za-z0-9_.\-]{1,200}$")
SW_SOURCE_ID  = re.compile(r"^-?\d{1,20}$")

M_EXT_UPDATE  = ("mutation($id: String!, $patch: UpdateExtensionPatchInput!) { "
                 "updateExtension(input: {id: $id, patch: $patch}) { extension { pkgName isInstalled hasUpdate } } }")
Q_REPOS       = "query { settings { extensionRepos } }"
M_REPOS_WRAP  = ("mutation($r: [String!]!) { setSettings(input: {settings: {extensionRepos: $r}}) "
                 "{ settings { extensionRepos } } }")
M_REPOS_FLAT  = ("mutation($r: [String!]!) { setSettings(input: {extensionRepos: $r}) "
                 "{ settings { extensionRepos } } }")

_sw_types       = {}                                 # type name -> set of field names (kept once it was read)
_sw_choice_lock = threading.Lock()
_sw_focus = {"id": ""}      # one picked source to ask on its own (the panel's per-source keys); "" = all picked


def _sw_fields(type_name):
    """The field names of a GraphQL type (object or input), or None when Suwayomi will not say."""
    got = _sw_types.get(type_name)
    if got is not None:
        return got
    try:
        t = sw_gql("query($n: String!) { __type(name: $n) { fields { name } inputFields { name } } }",
                   {"n": type_name})["__type"]
    except Exception:
        return None
    if not t:
        return None
    names = {f["name"] for f in ((t.get("fields") or []) + (t.get("inputFields") or []))}
    _sw_types[type_name] = names
    return names


def _sw_forget():
    """Installing or removing an extension changes the sources: drop what was cached about them."""
    _cache_drop("sw:sources")
    _cache_drop("sw:sorts:")
    _cache_drop("swlatest:")
    _cache_drop("swbrowse:")


# ── The sources the panel picked ──

def _sw_choice_path():
    return os.path.join(DATA_DIR, "sw_sources.json")


def sw_choice_get():
    """The source ids the Sources page picked, in order; None when nothing was picked (automatic)."""
    with _sw_choice_lock:
        try:
            with open(_sw_choice_path(), encoding="utf-8") as f:
                ids = json.load(f).get("sources")
        except (OSError, ValueError, AttributeError):
            return None
    ids = [str(i) for i in ids if SW_SOURCE_ID.match(str(i))] if isinstance(ids, list) else []
    return ids or None


def sw_choice_set(ids):
    """Keep `ids` as the pick; None or an empty list goes back to the automatic choice."""
    with _sw_choice_lock:
        p = _sw_choice_path()
        if not ids:
            try:
                os.remove(p)
            except OSError:
                pass
        else:
            tmp = p + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump({"sources": list(ids)}, f, indent=2)
            os.replace(tmp, p)
    _sw_forget()


def sw_sources_view():
    """Every installed source (any language, NSFW included) with whether Browse asks it now."""
    every = _sw_all_sources()
    try:
        used = {str(n["id"]) for n in _sw_sources()}
    except RuntimeError:                             # nothing installed that the automatic choice takes
        used = set()
    rows = [{"id": str(n["id"]), "name": n["name"], "lang": n["lang"], "latest": bool(n.get("supportsLatest")),
             "nsfw": bool(n.get("isNsfw")), "used": str(n["id"]) in used} for n in every]
    rows.sort(key=lambda r: (r["name"].lower(), r["lang"]))
    focus = _sw_focus["id"] if _sw_focus["id"] in used else ""
    return {"sources": rows, "custom": sw_choice_get() is not None, "lang": SW_LANG, "cap": SW_MAX_SOURCES,
            "focus": focus}


def sw_source_use(source_id, use):
    """Add one source to (or take it out of) what Browse asks. The first change turns the
    automatic choice into a pick: what is used now, plus or minus that source."""
    source_id = str(source_id or "")
    if not SW_SOURCE_ID.match(source_id):
        raise ValueError("bad source id")
    every = {str(n["id"]) for n in _sw_all_sources()}
    if source_id not in every:
        raise ValueError("that source is not installed")
    current = sw_choice_get()
    if current is None:
        try:
            current = [str(n["id"]) for n in _sw_sources()]
        except RuntimeError:
            current = []
    current = [i for i in current if i in every]
    if use and source_id not in current:
        current.append(source_id)                    # a new pick goes last: the earlier ones win a tie
    elif not use:
        current = [i for i in current if i != source_id]
        if _sw_focus["id"] == source_id:
            _sw_focus["id"] = ""
    if not current:
        raise ValueError("keep at least one source")
    sw_choice_set(current)
    return sw_sources_view()


def sw_sources_auto():
    sw_choice_set(None)
    return sw_sources_view()


def sw_focus_set(source_id):
    """Ask only one of the picked sources (the panel's per-source keys); "" asks all of them again.
    Not kept across a restart: the panel starts on all of them."""
    source_id = str(source_id or "")
    if source_id:
        if not SW_SOURCE_ID.match(source_id):
            raise ValueError("bad source id")
        if source_id not in {str(n["id"]) for n in _sw_sources()}:
            raise ValueError("that source is not one of the picked sources")
    _sw_focus["id"] = source_id
    return sw_sources_view()


# ── Repositories ──

def sw_repos_get():
    repos = sw_gql(Q_REPOS)["settings"].get("extensionRepos") or []
    return {"repos": list(repos), "suggested": SW_SUGGESTED_REPOS}


def _sw_clean_repos(repos):
    out = []
    for r in repos:
        r = str(r or "").strip()
        if not r:
            continue
        if not re.match(r"^https?://[^\s]+$", r, re.I):
            raise ValueError(f"not a web address: {r[:80]}")
        if r not in out:
            out.append(r)
    return out


def sw_repos_set(repos):
    clean = _sw_clean_repos(repos)
    have = _sw_fields("SetSettingsInput")
    queries = [M_REPOS_WRAP, M_REPOS_FLAT]
    if have is not None and "settings" not in have:  # this Suwayomi takes the settings flat
        queries.reverse()
    last = None
    for q in queries:
        try:
            sw_gql(q, {"r": clean})
            last = None
            break
        except Exception as e:                       # a GraphQL / HTTP error: the other shape may be the right one
            last = e
    if last:
        raise last
    return sw_repos_get()


def sw_repos_change(add=None, remove=None, repos=None):
    if repos is not None:
        return sw_repos_set(repos)
    cur = sw_repos_get()["repos"]
    if add:
        cur = cur + [add]
    if remove:
        cur = [r for r in cur if r != remove]
    return sw_repos_set(cur)


# ── Extensions ──

def _sw_ext_select():
    have = _sw_fields("ExtensionType")
    return " ".join(f for f in SW_EXT_WANT if have is None or f in have) if have \
        else " ".join(SW_EXT_BASE)


def _sw_ext_row(e):
    return {"pkg": e["pkgName"], "name": e.get("name") or e["pkgName"], "lang": e.get("lang") or "",
            "version": e.get("versionName") or "", "installed": bool(e.get("isInstalled")),
            "update": bool(e.get("hasUpdate")), "obsolete": bool(e.get("isObsolete")),
            "nsfw": bool(e.get("isNsfw")), "icon": _sw_thumb(e.get("iconUrl")),
            "repo": e.get("repo") or ""}


def sw_extensions(refresh=False):
    sel = _sw_ext_select()
    if refresh:                                      # asks every repository again: a network round trip
        nodes = sw_gql("mutation { fetchExtensions(input: {}) { extensions { %s } } }" % sel,
                       timeout=180)["fetchExtensions"]["extensions"]
    else:
        nodes = sw_gql("query { extensions { nodes { %s } } }" % sel, timeout=120)["extensions"]["nodes"]
    rows = [_sw_ext_row(e) for e in nodes]
    rows.sort(key=lambda r: (not r["installed"], not r["update"], r["name"].lower(), r["lang"]))
    langs = sorted({r["lang"] for r in rows if r["lang"]})
    return {"extensions": rows, "langs": langs, "lang": SW_LANG, "nsfw": SW_NSFW}


def sw_ext_action(action, pkg):
    """Install, update or uninstall one extension (an install downloads its apk: it can take a while)."""
    if action not in ("install", "update", "uninstall"):
        raise ValueError("action must be install, update or uninstall")
    if not SW_EXT_PKG_RE.match(str(pkg or "")):
        raise ValueError("bad extension package name")
    before = {str(n["id"]) for n in _sw_all_sources()}
    sw_gql(M_EXT_UPDATE, {"id": pkg, "patch": {action: True}}, timeout=300)
    _sw_forget()
    after = {str(n["id"]): n for n in _sw_all_sources()}
    picked = sw_choice_get()
    if picked is not None:                           # a hand-made pick should not hide a source just installed
        keep = [i for i in picked if i in after]
        if action == "install":
            keep += [i for i in after if i not in before and i not in keep]
        if keep != picked:
            sw_choice_set(keep or None)
    added = [after[i]["name"] for i in after if i not in before]
    return {"ok": True, "action": action, "pkg": pkg, "newSources": added}


def sw_ext_update_all():
    done, failed = [], []
    for e in sw_extensions()["extensions"]:
        if e["installed"] and e["update"]:
            try:
                sw_ext_action("update", e["pkg"])
                done.append(e["pkg"])
            except Exception as ex:
                print(f"[manga-server] suwayomi update {e['pkg']}: {ex}", flush=True)
                failed.append(e["pkg"])
    return {"ok": not failed, "updated": done, "failed": failed}


def sw_status():
    return {"enabled": SW_ENABLED, "url": SW_URL, "running": SW_ENABLED and _sw_up(),
            "canStart": bool(SW_CMD), "custom": sw_choice_get() is not None,
            "lang": SW_LANG, "nsfw": SW_NSFW}


# ── Favorites ──────────────────────────────────────────────────────────────

_fav_lock = threading.Lock()


def _load_favs():
    with _fav_lock:
        if not os.path.exists(FAVORITES_FILE):
            return []
        with open(FAVORITES_FILE) as f:
            return json.load(f)


def _save_favs(favs):
    with _fav_lock:
        with open(FAVORITES_FILE, "w") as f:
            json.dump(favs, f, indent=2)


def fav_list():
    favs = _load_favs()
    return [{**f, "image": proxy_url(f["image"])} for f in favs]


def fav_add(manga_id, title, raw_image_url):
    favs = _load_favs()
    if any(f["id"] == manga_id for f in favs):
        return {"ok": True}
    favs.append({
        "id":                    manga_id,
        "title":                 title,
        "image":                 raw_image_url,
        "addedAt":               datetime.now(timezone.utc).isoformat(),
        "lastKnownChapterCount": 0,
        "latestSeenChapterId":   "",
        "hasNewChapters":        False,
    })
    _save_favs(favs)
    return {"ok": True}


def fav_remove(manga_id):
    favs = _load_favs()
    _save_favs([f for f in favs if f["id"] != manga_id])
    return {"ok": True}


def fav_mark_seen(manga_id, chapter_id):
    favs = _load_favs()
    for f in favs:
        if f["id"] == manga_id:
            f["latestSeenChapterId"] = chapter_id
            f["hasNewChapters"]      = False
    _save_favs(favs)
    return {"ok": True}


def fav_check():
    favs    = _load_favs()
    updated = []

    def _check_one(fav):
        key = f"info:{fav['id']}"
        with _cache_lock:
            _cache.pop(key, None)
        try:
            data  = info(fav["id"])
            count = len(data.get("chapters", []))
            if count > fav.get("lastKnownChapterCount", 0):
                fav["hasNewChapters"]        = True
                fav["lastKnownChapterCount"] = count
                updated.append({"id": fav["id"], "title": fav["title"], "newCount": count})
            elif not fav.get("hasNewChapters"):
                fav["lastKnownChapterCount"] = count
        except Exception:
            pass

    with ThreadPoolExecutor(max_workers=4) as ex:
        list(ex.map(_check_one, favs))
    _save_favs(favs)
    return {"checked": len(favs), "updated": updated}


# ── Downloads ──────────────────────────────────────────────────────────────

_dl_jobs = {}
_dl_lock = threading.Lock()


def dl_list():
    result = []
    if not os.path.exists(DOWNLOADS_DIR):
        return result
    for sid in sorted(os.listdir(DOWNLOADS_DIR)):
        series_dir  = os.path.join(DOWNLOADS_DIR, sid)
        series_meta = os.path.join(series_dir, "series_meta.json")
        if not os.path.isdir(series_dir) or not os.path.exists(series_meta):
            continue
        with open(series_meta) as f:
            sm = json.load(f)
        chapters = []
        for cid in sorted(os.listdir(series_dir)):
            ch_dir  = os.path.join(series_dir, cid)
            ch_meta = os.path.join(ch_dir, "meta.json")
            if not os.path.isdir(ch_dir) or not os.path.exists(ch_meta):
                continue
            with open(ch_meta) as f:
                chapters.append(json.load(f))
        chapters.sort(key=lambda c: chapter_sort_num(c.get("chapterNum")), reverse=True)
        cover_path      = os.path.join(series_dir, "cover.jpg")
        cover_url_local = f"file://{cover_path}" if os.path.exists(cover_path) else proxy_url(sm.get("rawCoverUrl", ""))
        result.append({**sm, "image": cover_url_local, "chapters": chapters})
    return result


def dl_progress(chapter_id):
    with _dl_lock:
        return _dl_jobs.get(chapter_id, {"status": "not_started"})


def dl_start(manga_id, chapter_id, chapter_num, chapter_title, manga_title, raw_cover_url):
    with _dl_lock:
        job = _dl_jobs.get(chapter_id, {})
        if job.get("status") in ("downloading", "done"):
            return {"ok": False, "message": job["status"]}
        _dl_jobs[chapter_id] = {"status": "pending", "total": 0, "done": 0, "error": None}
    threading.Thread(
        target=_dl_worker,
        args=(manga_id, chapter_id, chapter_num, chapter_title, manga_title, raw_cover_url),
        daemon=True
    ).start()
    return {"ok": True}


def _dl_worker(manga_id, chapter_id, chapter_num, chapter_title, manga_title, raw_cover_url):
    sid    = manga_id.split("/")[0]
    ch_dir = os.path.join(DOWNLOADS_DIR, sid, chapter_id)
    os.makedirs(ch_dir, exist_ok=True)

    try:
        page_list = _pages(chapter_id)
        total     = len(page_list)
        with _dl_lock:
            _dl_jobs[chapter_id].update({"status": "downloading", "total": total})

        for pg in page_list:
            if provider_of(chapter_id) != "weebcentral":
                body, ctype = page_bytes(chapter_id, pg["page"] - 1)
                ext = {"image/png": "png", "image/webp": "webp"}.get(ctype.split(";")[0].strip(), "jpg")
                fname = os.path.join(ch_dir, f"{pg['page']:03d}.{ext}")
                if not os.path.exists(fname):
                    with open(fname, "wb") as f:
                        f.write(body)
                with _dl_lock:
                    _dl_jobs[chapter_id]["done"] += 1
                continue
            qs       = parse_qs(urlparse(pg["img"]).query)
            real_url = unquote(qs.get("url", [""])[0])
            if not real_url:
                continue
            ext   = real_url.split("?")[0].rsplit(".", 1)[-1].lower()
            ext   = ext if ext in ("jpg", "jpeg", "png", "webp") else "jpg"
            fname = os.path.join(ch_dir, f"{pg['page']:03d}.{ext}")
            if not os.path.exists(fname):
                cached = _img_get(real_url)
                if cached:
                    body = cached[0]
                else:
                    body, ctype = _raw_get(real_url)
                    _img_put(real_url, body, ctype)
                with open(fname, "wb") as f:
                    f.write(body)
            with _dl_lock:
                _dl_jobs[chapter_id]["done"] += 1

        with open(os.path.join(ch_dir, "meta.json"), "w") as f:
            json.dump({
                "chapterId":    chapter_id,
                "chapterNum":   chapter_num,
                "title":        chapter_title,
                "mangaId":      manga_id,
                "mangaTitle":   manga_title,
                "pages":        total,
                "downloadedAt": datetime.now(timezone.utc).isoformat(),
            }, f)

        series_dir  = os.path.join(DOWNLOADS_DIR, sid)
        series_meta = os.path.join(series_dir, "series_meta.json")
        with open(series_meta, "w") as f:
            json.dump({"id": manga_id, "title": manga_title,
                       "localId": sid, "rawCoverUrl": raw_cover_url}, f)

        cover_path = os.path.join(series_dir, "cover.jpg")
        if not os.path.exists(cover_path) and raw_cover_url:
            try:
                body, _ = _raw_get(raw_cover_url, timeout=15)
                with open(cover_path, "wb") as f:
                    f.write(body)
            except Exception:
                pass

        with _dl_lock:
            _dl_jobs[chapter_id]["status"] = "done"

    except Exception as e:
        import traceback; traceback.print_exc()
        with _dl_lock:
            _dl_jobs[chapter_id] = {"status": "error", "total": 0, "done": 0, "error": str(e)}


def dl_pages(chapter_id):
    for sid in os.listdir(DOWNLOADS_DIR):
        ch_dir = os.path.join(DOWNLOADS_DIR, sid, chapter_id)
        if os.path.isdir(ch_dir):
            files = sorted(f for f in os.listdir(ch_dir)
                           if f[0].isdigit() and f.rsplit(".", 1)[-1].lower()
                           in ("jpg", "jpeg", "png", "webp"))
            return [{"page": i + 1, "img": f"file://{os.path.join(ch_dir, fn)}"}
                    for i, fn in enumerate(files)]
    return []


def dl_remove(chapter_id):
    for sid in os.listdir(DOWNLOADS_DIR):
        ch_dir = os.path.join(DOWNLOADS_DIR, sid, chapter_id)
        if os.path.isdir(ch_dir):
            shutil.rmtree(ch_dir)
            series_dir = os.path.join(DOWNLOADS_DIR, sid)
            remaining  = [d for d in os.listdir(series_dir) if os.path.isdir(os.path.join(series_dir, d))]
            if not remaining:
                shutil.rmtree(series_dir)
            with _dl_lock:
                _dl_jobs.pop(chapter_id, None)
            return {"ok": True}
    return {"ok": False, "error": "not found"}


# ── Image byte cache ───────────────────────────────────────────────────────

_img_cache      = {}
_img_cache_lock = threading.Lock()
_img_cache_max  = 600
_img_sem        = threading.Semaphore(10)


def _img_get(url):
    with _img_cache_lock:
        return _img_cache.get(url)


def _img_put(url, body, ctype):
    with _img_cache_lock:
        if len(_img_cache) >= _img_cache_max:
            _img_cache.pop(next(iter(_img_cache)))
        _img_cache[url] = (body, ctype)


def _send_image(handler, body, ctype):
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "public, max-age=86400")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    try:
        handler.wfile.write(body)
    except (BrokenPipeError, ConnectionResetError):
        pass


# ── Image proxy ─────────────────────────────────────────────────────────────

def proxy_image(handler, img_url):
    cached = _img_get(img_url)
    if cached:
        _send_image(handler, *cached)
        return

    with _img_sem:
        body, ctype = _raw_get(img_url)

    _img_put(img_url, body, ctype)
    _send_image(handler, body, ctype)


# ── HTTP Server ────────────────────────────────────────────────────────────

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads      = True
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[manga-server] {fmt % args}")

    def _json(self, data, status=200, cors=True):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if cors:                       # the login endpoints are not for other web pages
            self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _html(self, page, status=200):
        body = page.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; script-src 'unsafe-inline'; "
                         "style-src 'unsafe-inline'; connect-src 'self'")
        self.end_headers()
        self.wfile.write(body)

    def _local_only(self):
        """The login endpoints answer the panel and the callback page only: a request that
        names another host (DNS rebinding) or comes from another origin is refused."""
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].lower()
        origin = self.headers.get("Origin")
        ok = host in ("127.0.0.1", "localhost") and (
            not origin or origin in (f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"))
        if not ok:
            self._json({"error": "not allowed"}, 403, cors=False)
        return ok

    def _error(self, msg, status=500):
        self._json({"error": msg}, status)

    def do_HEAD(self):
        parsed = urlparse(self.path)
        if parsed.path == "/image":
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        qs     = parse_qs(parsed.query)

        def param(key, default=""):
            return (qs.get(key) or [default])[0]

        try:
            p = parsed.path

            if p == "/hot":
                self._json(hot_updates() if provider_get() == "weebcentral" else source_latest(1)["results"])
            elif p == "/latest":
                pg = int(param("page", "1"))
                self._json(source_latest(pg))
            elif p == "/browse":
                try:
                    self._json(source_browse(param("sort", "popular"), int(param("page", "1"))))
                except ValueError as e:
                    self._error(str(e), 400)
            elif p == "/provider":
                if self._local_only():
                    self._json(provider_status(), cors=False)
            elif p == "/mdpage":
                cid, idx = param("c"), param("i")
                if not (is_md(cid) and idx.isdigit()):
                    return self._error("missing or bad c / i", 400)
                with _img_sem:
                    body, ctype = md_page_bytes(cid, int(idx))
                _send_image(self, body, ctype)
            elif p.startswith("/sw/"):
                if not self._local_only():
                    return
                if p == "/sw/status":
                    return self._json(sw_status(), cors=False)
                if not SW_ENABLED:
                    return self._json({"error": "Suwayomi is not set up (run install-deps.sh)"}, 400, cors=False)
                try:
                    if p == "/sw/extensions":
                        self._json(sw_extensions(param("refresh") == "1"), cors=False)
                    elif p == "/sw/repos":
                        self._json(sw_repos_get(), cors=False)
                    elif p == "/sw/sources":
                        self._json(sw_sources_view(), cors=False)
                    else:
                        self._json({"error": "not found"}, 404, cors=False)
                except ValueError as e:
                    self._json({"error": str(e)}, 400, cors=False)
            elif p == "/swpage":
                cid, idx = param("c"), param("i")
                if not (is_sw(cid) and idx.isdigit()):
                    return self._error("missing or bad c / i", 400)
                with _img_sem:
                    body, ctype = sw_page_bytes(cid, int(idx))
                _send_image(self, body, ctype)
            elif p == "/search":
                q = param("q")
                if not q:
                    return self._error("missing q", 400)
                if provider_get() == "mangadex":
                    return self._json(md_search(q, int(param("offset", "0"))))
                if provider_get() == "suwayomi":
                    return self._json(sw_search(q, int(param("offset", "0"))))
                self._json(search(q, param("type") or None,
                                  int(param("offset", "0")),
                                  param("sort", "Latest Updates")))
            elif p == "/info":
                mid = param("id")
                if not mid:
                    return self._error("missing id", 400)
                self._json(info_for_ui(mid))
            elif p == "/al/browse":
                def _int(name):
                    v = param(name, "0")
                    return int(v) if v.lstrip("-").isdigit() else 0
                self._json(al_browse(
                    param("q"),
                    [g for g in param("genres").split(",") if g],
                    param("format"), param("country"), param("status"),
                    _int("year"), param("sort"),
                    param("adult") == "1", max(1, _int("page")),
                    [t for t in param("tags").split("|") if t],
                    _int("score_min"), _int("score_max")))
            elif p == "/al/tags":
                self._json(al_tags())
            elif p == "/al/auth/status":
                if self._local_only():
                    self._json(auth_status(), cors=False)
            elif p == "/al/auth/callback":
                if self._local_only():
                    self._html(auth_callback_html())
            elif p == "/al/track":
                if self._local_only():
                    self._json(al_track_info(param("id")), cors=False)
            elif p == "/al/list":
                if self._local_only():
                    yr = param("year", "0")
                    self._json(al_list(
                        param("status", "CURRENT"), param("q"), param("format"), param("country"),
                        [g for g in param("genres").split(",") if g],
                        [t for t in param("tags").split("|") if t],
                        int(yr) if yr.isdigit() else 0, param("mstatus"), param("sort", "SCORE")),
                        cors=False)
            elif p == "/al/profile":
                if self._local_only():
                    self._json(al_profile(param("fresh") == "1"), cors=False)
            elif p == "/al/overview":
                if self._local_only():
                    self._json(al_overview(), cors=False)
            elif p == "/al/pick":
                if self._local_only():
                    ex = param("exclude")
                    self._json(al_pick(ex if ex.isdigit() else ""), cors=False)
            elif p == "/al/activity":
                if self._local_only():
                    self._json(al_activity(param("fresh") == "1"), cors=False)
            elif p == "/al/extras":
                if self._local_only():
                    self._json(al_extras(), cors=False)
            elif p == "/al/recs":
                if self._local_only():
                    self._json(al_recs(), cors=False)
            elif p == "/al/info":
                aid = param("id")
                if not aid.isdigit():
                    return self._error("missing or bad id", 400)
                self._json(al_detail(aid))
            elif p == "/al/candidates":
                aid = param("anilistId")
                if not aid.isdigit():
                    return self._error("missing or bad anilistId", 400)
                self._json(al_candidates(aid, param("q")))
            elif p == "/pages":
                cid = param("chapterId")
                if not cid:
                    return self._error("missing chapterId", 400)
                self._json(pages(cid))
            elif p == "/image":
                img_url = unquote(param("url"))
                if not img_url:
                    return self._error("missing url", 400)
                proxy_image(self, img_url)
            elif p == "/favorites":
                self._json(fav_list())
            elif p == "/favorites/check":
                self._json(fav_check())
            elif p == "/dl/list":
                self._json(dl_list())
            elif p == "/dl/progress":
                cid = param("chapterId")
                if not cid:
                    return self._error("missing chapterId", 400)
                self._json(dl_progress(cid))
            elif p == "/dl/pages":
                cid = param("chapterId")
                if not cid:
                    return self._error("missing chapterId", 400)
                self._json(dl_pages(cid))
            elif p == "/health":
                self._json({"ok": True})
            else:
                self._error("not found", 404)

        except (BrokenPipeError, ConnectionResetError):
            pass
        except AuthError as e:
            self._json({"error": str(e)}, e.status, cors=False)
        except Exception as e:
            import traceback; traceback.print_exc()
            self._error(str(e))

    def do_POST(self):
        parsed = urlparse(self.path)
        try:
            length = int(self.headers.get("Content-Length", 0))
            body   = json.loads(self.rfile.read(length)) if length else {}
        except Exception:
            return self._error("bad request body", 400)

        try:
            p = parsed.path

            if p == "/favorites/add":
                manga_id = body.get("id", "")
                if not manga_id:
                    return self._error("missing id", 400)
                self._json(fav_add(manga_id, body.get("title", ""), body.get("imageUrl", "")))
            elif p == "/favorites/remove":
                manga_id = body.get("id", "")
                if not manga_id:
                    return self._error("missing id", 400)
                self._json(fav_remove(manga_id))
            elif p == "/favorites/mark-seen":
                manga_id = body.get("id", "")
                if not manga_id:
                    return self._error("missing id", 400)
                self._json(fav_mark_seen(manga_id, body.get("chapterId", "")))
            elif p == "/al/match/set":
                aid, wc_id = str(body.get("anilistId", "")), body.get("id", "")
                if not (aid.isdigit() and wc_id):
                    return self._error("missing anilistId or id", 400)
                match_set(aid, wc_id, body.get("title", ""), True, 1.0)
                self._json({"ok": True})
            elif p == "/al/match/clear":
                aid = str(body.get("anilistId", ""))
                if not aid.isdigit():
                    return self._error("missing anilistId", 400)
                match_clear(aid)
                self._json({"ok": True})
            elif p == "/provider":
                if not self._local_only():
                    return
                self._json(provider_set(body.get("provider")), cors=False)
            elif p.startswith("/sw/"):
                if not self._local_only():
                    return
                if not SW_ENABLED:
                    return self._json({"error": "Suwayomi is not set up (run install-deps.sh)"}, 400, cors=False)
                try:
                    if p == "/sw/ext":
                        if body.get("action") == "update-all":
                            self._json(sw_ext_update_all(), cors=False)
                        else:
                            self._json(sw_ext_action(body.get("action"), body.get("pkg")), cors=False)
                    elif p == "/sw/repos":
                        self._json(sw_repos_change(body.get("add"), body.get("remove"), body.get("repos")),
                                   cors=False)
                    elif p == "/sw/sources":
                        if body.get("auto"):
                            self._json(sw_sources_auto(), cors=False)
                        elif "focus" in body:
                            self._json(sw_focus_set(body.get("focus")), cors=False)
                        else:
                            self._json(sw_source_use(body.get("id"), bool(body.get("use"))), cors=False)
                    else:
                        self._json({"error": "not found"}, 404, cors=False)
                except ValueError as e:
                    self._json({"error": str(e)}, 400, cors=False)
            elif p in ("/al/track/progress", "/al/track/set"):
                if not self._local_only():
                    return
                if p == "/al/track/progress":
                    self._json(al_track_progress(body.get("anilistId"), body.get("progress"),
                                                 body.get("volumes")), cors=False)
                else:
                    self._json(al_track_set(body.get("anilistId"), body.get("status"),
                                            body.get("progress"), body.get("volumes")), cors=False)
            elif p.startswith("/al/auth/"):
                if not self._local_only():
                    return
                if p == "/al/auth/client":
                    self._json(auth_set_client(body.get("clientId")), cors=False)
                elif p == "/al/auth/start":
                    self._json(auth_start(), cors=False)
                elif p == "/al/auth/token":
                    self._json(auth_token(body.get("token"), body.get("nonce")), cors=False)
                elif p == "/al/auth/logout":
                    self._json(auth_logout(), cors=False)
                else:
                    self._error("not found", 404)
            elif p == "/dl/start":
                manga_id   = body.get("mangaId", "")
                chapter_id = body.get("chapterId", "")
                if not (manga_id and chapter_id):
                    return self._error("missing mangaId or chapterId", 400)
                self._json(dl_start(manga_id, chapter_id,
                                    body.get("chapterNum", ""),
                                    body.get("chapterTitle", ""),
                                    body.get("mangaTitle", ""),
                                    body.get("rawCoverUrl", "")))
            elif p == "/dl/delete":
                chapter_id = body.get("chapterId", "")
                if not chapter_id:
                    return self._error("missing chapterId", 400)
                self._json(dl_remove(chapter_id))
            else:
                self._error("not found", 404)

        except (BrokenPipeError, ConnectionResetError):
            pass
        except AuthError as e:
            self._json({"error": str(e)}, e.status, cors=False)
        except Exception as e:
            import traceback; traceback.print_exc()
            self._error(str(e))


def exit_with_parent():
    """Quit once the shell that started us is gone: a killed Quickshell
    leaves its children running, and a stale server would hold the port."""
    parent = os.getppid()

    def watch():
        while os.getppid() == parent:
            time.sleep(2)
        sw_stop()                      # os._exit skips atexit, so end Suwayomi by hand
        os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def run():
    import signal
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))   # a plain `kill` exits cleanly
    exit_with_parent()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[manga-server] Listening on http://127.0.0.1:{PORT} (threaded)")
    server.serve_forever()


if __name__ == "__main__":
    run()