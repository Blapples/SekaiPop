# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
Shared utilities: HTTP session, fetch helpers, TTL cache, text cleaning.
Imported by providers — never by server.py directly.
"""

import html as _html
import json
import re
import time
import threading
from urllib.parse import quote, urlsplit

# ── HTTP session (curl_cffi preferred for Cloudflare bypass) ───────────────
# Sessions are checked out of a pool, one per request in flight: the server
# handles each request on its own thread, and a curl_cffi session used by two
# threads at once corrupts libcurl state — random TLS errors, and under a
# burst of cover requests an abort() that takes the whole server down. The
# pool (rather than one session per thread) keeps connections warm, since the
# server starts a fresh thread for every request.

try:
    from curl_cffi.requests import Session as _SessionClass
    _SESSION_KW = {"impersonate": "firefox"}
    _USE_CFFI = True
    print("[novel-utils] Using curl_cffi (Firefox impersonation)")
except ImportError:
    from requests import Session as _SessionClass
    _SESSION_KW = {}
    _USE_CFFI = False
    print("[novel-utils] curl_cffi not found – falling back to requests")

_pool: list = []
_pool_lock = threading.Lock()


def _get(url: str, headers: dict, timeout: int, attempts: int = 3, data=None):
    # A burst of new connections (a grid of covers) sometimes gets its TLS
    # handshake refused; those connection-level failures are retried with a
    # fresh session after a short backoff. HTTP error statuses are not.
    for attempt in range(attempts):
        with _pool_lock:
            s = _pool.pop() if _pool else None
        if s is None:
            s = _SessionClass(**_SESSION_KW)
        try:
            if data is None:
                r = s.get(url, headers=headers, timeout=timeout)
            else:
                r = s.post(url, headers=headers, data=data, timeout=timeout)
        except Exception:
            try:
                s.close()
            except Exception:
                pass
            if attempt == attempts - 1:
                raise
            time.sleep(0.3 * (attempt + 1))
            continue
        with _pool_lock:
            _pool.append(s)
        return r

BASE_HEADERS = {
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

AJAX_HEADERS = {
    **BASE_HEADERS,
    "X-Requested-With": "XMLHttpRequest",
    "Sec-Fetch-Dest":   "empty",
    "Sec-Fetch-Mode":   "cors",
    "Sec-Fetch-Site":   "same-origin",
}

# ── Page-request pacing ────────────────────────────────────────────────────
# The site rate-limits page and ajax requests (not images) over a rolling
# window: measured 2026-09-28, one request every ~0.9 s (start to start) ran
# 40 in a row cleanly, while ~0.6 s tripped HTTP 429 on the 24th and ~0.4 s on
# the 15th; it clears ~10 s after tripping. A long novel's chapter list is a
# dozen or more requests back to back, so every page request waits for its
# slot, and a 429 that slips through (other clients, a browser on the same IP)
# is waited out and retried rather than failing the whole call.
# Slots are kept per host, so one source's pacing never delays another's.

PAGE_INTERVAL = 0.8
_RATE_WAIT    = 6.0
_RATE_TRIES   = 4

_pace_lock  = threading.Lock()
_next_slot: dict = {}


def _pace(host: str):
    with _pace_lock:
        now  = time.monotonic()
        slot = max(now, _next_slot.get(host, 0.0))
        _next_slot[host] = slot + PAGE_INTERVAL
    if slot > now:
        time.sleep(slot - now)


def _backoff(host: str, seconds: float):
    """Push every waiting page request back, not just the one that tripped."""
    with _pace_lock:
        _next_slot[host] = max(_next_slot.get(host, 0.0), time.monotonic() + seconds)


def fetch(url: str, extra_headers: dict | None = None, timeout: int = 30,
          form: dict | None = None) -> str:
    """GET url (or POST `form` to it, url-encoded), return response text.
    Raises on non-2xx."""
    headers = {**BASE_HEADERS, **(extra_headers or {})}
    if form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    host = urlsplit(url).netloc
    for attempt in range(_RATE_TRIES):
        _pace(host)
        r = _get(url, headers, timeout, data=form)
        if r.status_code != 429 or attempt == _RATE_TRIES - 1:
            break
        try:
            wait = float(r.headers.get("Retry-After") or 0)
        except ValueError:
            wait = 0
        wait = max(wait, _RATE_WAIT * (attempt + 1))
        print(f"[novel-utils] 429 from site, waiting {wait:.0f}s: {url}")
        _backoff(host, wait)
    r.raise_for_status()
    return r.text


def fetch_json(url: str, extra_headers: dict | None = None, timeout: int = 30):
    """GET url and decode its JSON body. Raises on non-2xx or bad JSON."""
    return json.loads(fetch(url, {"Accept": "application/json",
                                  **(extra_headers or {})}, timeout))


def fetch_bytes(url: str, timeout: int = 30) -> tuple[bytes, str]:
    """GET url, return (body_bytes, content_type). Used for image proxy."""
    r = _get(url, BASE_HEADERS, timeout)
    r.raise_for_status()
    return r.content, r.headers.get("Content-Type", "image/jpeg")


# ── TTL cache (shared across all providers) ────────────────────────────────
# Keys are namespaced per provider: "{provider_name}:{endpoint}:{id}"

_cache:      dict = {}
_cache_lock: threading.Lock = threading.Lock()


def cached(key: str, ttl: int, fn):
    """Return cached value for key, or call fn() and cache the result."""
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


def cache_invalidate(key: str):
    with _cache_lock:
        _cache.pop(key, None)


# ── Text cleaning ──────────────────────────────────────────────────────────

def clean_text(html: str) -> str:
    """Strip all HTML tags, decode entities and normalise whitespace.
    Entities are decoded after the tags are gone, so an escaped "&lt;b&gt;"
    in the text survives as literal "<b>" instead of being stripped. The site
    double-encodes some text ("&amp;amp;", "&amp;#39;"), so decoding repeats
    until nothing changes."""
    text = re.sub(r"<[^>]+>", " ", html)
    for _ in range(3):
        decoded = _html.unescape(text)
        if decoded == text:
            break
        text = decoded
    return re.sub(r"\s+", " ", text).strip()
