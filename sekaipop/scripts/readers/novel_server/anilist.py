"""AniList tracking for the novel reader.

Only novels: every search asks for AniList's NOVEL format (light novels and web novels are
MANGA-type media with format NOVEL on AniList), and a title that is not a NOVEL is refused when it
is tracked, so manga never ends up on the list through this reader.

The login is the manga reader's: it runs the AniList login (manga_server.py, /al/auth/*) and keeps
the token in anilist_auth.json (mode 600) in the manga data folder. This module reads that file and
uses the token to act as the user; it never writes it, never returns it, and a login that AniList
turns down is left for the manga server to drop. So logging in once, in either reader, serves both.

  match_get / match_set / match_clear   which AniList novel a novel from the source is (kept in
                                        novel/anilist_matches.json, per source id)
  search                                AniList novels by name (to pick a match by hand)
  browse / tags / info                  Discover: AniList's novels with filters (genre, tags, origin,
                                        status, score, year, length, sort), AniList's tag list, and one
                                        novel's page. Novels only, no login needed.
  track_info / track_progress / track_set
                                        the logged-in user's list entry, the way the manga reader does
                                        it: progress only ever goes up, a new entry becomes Reading,
                                        the last chapter AniList knows makes it Completed; the track
                                        sheet may set anything.
"""

import difflib
import html
import json
import os
import re
import threading
import time
import unicodedata
import urllib.error
import urllib.request

ANILIST_URL = "https://graphql.anilist.co"
MANGA_DIR   = os.path.expanduser("~/.local/share/sekaipop/readers/manga")
NOVEL_DIR   = os.path.expanduser("~/.local/share/sekaipop/readers/novel")
AUTH_FILE   = os.path.join(MANGA_DIR, "anilist_auth.json")
MATCH_FILE  = os.path.join(NOVEL_DIR, "anilist_matches.json")

MATCH_MIN        = 0.88          # how close a name must be for an automatic match
AL_FORMAT        = "NOVEL"
AL_LIST_STATUSES = ("CURRENT", "PLANNING", "COMPLETED", "DROPPED", "PAUSED", "REPEATING")
AL_TRACK_MAX     = 100000


class AlError(Exception):
    def __init__(self, msg, status=400):
        super().__init__(msg)
        self.status = status


# ── The login (the manga reader's file) ─────────────────────────────────────

def _auth_read():
    try:
        with open(AUTH_FILE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _auth_live():
    data = _auth_read()
    if not data.get("token"):
        return {}
    exp = data.get("expiresAt") or 0
    if exp and exp < time.time():
        return {}
    return data


def status():
    data, live = _auth_read(), _auth_live()
    viewer = live.get("viewer") if live and isinstance(live.get("viewer"), dict) else None
    return {
        "loggedIn": bool(live),
        "expired":  bool(data.get("token")) and not live,
        "viewer":   viewer,
    }


def _token():
    t = _auth_live().get("token")
    if not t:
        raise AlError("Log in to AniList first (the key in the reader's header)", 401)
    return t


# ── AniList's GraphQL ───────────────────────────────────────────────────────

def _request(query, variables, token=None):
    """POST a GraphQL query; returns `data`. A test replaces this."""
    headers = {
        "Content-Type": "application/json",
        "Accept":       "application/json",
        "User-Agent":   "SekaiPop-novel-reader",
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(ANILIST_URL, data=body, headers=headers, method="POST")
    for attempt in (0, 1):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                payload = json.loads(r.read().decode("utf-8", "replace"))
            break
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            if e.code == 429 and attempt == 0:           # the per-minute limit: wait it out once
                try:
                    time.sleep(min(int(e.headers.get("Retry-After", "2")), 8))
                except ValueError:
                    time.sleep(2)
                continue
            if e.code == 401:
                raise AlError("Your AniList login has run out. Log in again.", 401)
            try:
                payload = json.loads(raw)
            except ValueError:
                raise AlError("AniList answered %d" % e.code, 502)
            break
        except (urllib.error.URLError, OSError) as e:
            raise AlError("Could not reach AniList: %s" % e, 502)
    errors = payload.get("errors") or []
    if any("invalid token" in str(e.get("message", "")).lower() for e in errors):
        raise AlError("Your AniList login has run out. Log in again.", 401)
    if errors:
        raise AlError("AniList: " + "; ".join(str(e.get("message")) for e in errors), 502)
    return payload.get("data") or {}


def _title(m):
    t = m.get("title") or {}
    return t.get("english") or t.get("romaji") or t.get("native") or "?"


_MEDIA_FIELDS = """id format chapters volumes status siteUrl synonyms
  title { romaji english native }
  coverImage { large extraLarge }
  startDate { year }"""

_SEARCH_Q = """
query ($q:String) {
  Page(perPage: 12) { media(search:$q, type:MANGA, format:NOVEL, sort:SEARCH_MATCH) { %s } }
}
""" % _MEDIA_FIELDS


def _card(m):
    cover = m.get("coverImage") or {}
    return {
        "anilistId": m.get("id") or 0,
        "title":     _title(m),
        "cover":     cover.get("large") or cover.get("extraLarge") or "",
        "year":      (m.get("startDate") or {}).get("year") or 0,
        "chapters":  m.get("chapters") or 0,
        "volumes":   m.get("volumes") or 0,
        "status":    m.get("status") or "",
        "siteUrl":   m.get("siteUrl") or "",
    }


def search(query):
    """AniList novels whose name matches `query` (needs no login)."""
    q = (query or "").strip()
    if not q:
        return []
    media = (_request(_SEARCH_Q, {"q": q}).get("Page") or {}).get("media") or []
    return [_card(m) for m in media if (m.get("format") or AL_FORMAT) == AL_FORMAT]


# ── Discover: AniList's novels with filters ─────────────────────────────────
# Same idea as the manga reader's Discover, but the format is always NOVEL and the filters are the
# ones that mean something for novels: where it comes from (Japan = light novels, Korea / China =
# web novels), how long it is (volumes for light novels, chapters for web novels), and the usual
# genre / tags / status / score / year. A login is not needed.

AL_PER_PAGE  = 30
TTL_BROWSE   = 600
TTL_INFO     = 1800
TTL_TAGS     = 7 * 86400            # the tag list changes about never
TAGS_FILE    = os.path.join(NOVEL_DIR, "al_tags.json")
AL_TAG_MAX   = 12                   # tags in one search, so a URL stays sane
AL_SORTS     = {"TRENDING_DESC", "POPULARITY_DESC", "SCORE_DESC", "FAVOURITES_DESC",
                "START_DATE_DESC", "UPDATED_AT_DESC", "SEARCH_MATCH"}
AL_STATUSES  = {"RELEASING", "FINISHED", "NOT_YET_RELEASED", "CANCELLED", "HIATUS"}
AL_COUNTRIES = {"JP", "KR", "CN", "TW"}
AL_GENRES    = {"Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror",
                "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance",
                "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"}
AL_LEN_MAX   = 100000               # a volume / chapter count the panel may ask for

_STATUS_LABEL = {
    "RELEASING": "Releasing", "FINISHED": "Finished", "NOT_YET_RELEASED": "Upcoming",
    "CANCELLED": "Cancelled", "HIATUS": "Hiatus",
}
# Country of origin -> the tag on a card (AniList has one NOVEL format; where it is from is the
# useful difference: Japanese ones are light novels, Korean and Chinese ones mostly web novels)
_TYPE_LABEL = {"JP": "LIGHT NOVEL", "KR": "KOREAN NOVEL", "CN": "CHINESE NOVEL", "TW": "TAIWAN NOVEL"}

_CARD_FIELDS = """id title{romaji english native} coverImage{large extraLarge} format status
  startDate{year} averageScore genres countryOfOrigin volumes chapters"""

_BROWSE_Q = """
query ($page:Int,$perPage:Int,$search:String,$sort:[MediaSort],$genre_in:[String],
       $tag_in:[String],$status_in:[MediaStatus],$country:CountryCode,
       $sd_gt:FuzzyDateInt,$sd_lt:FuzzyDateInt,$score_gt:Int,$score_lt:Int,
       $vol_gt:Int,$vol_lt:Int,$ch_gt:Int,$ch_lt:Int,$adult:Boolean) {
  Page(page:$page, perPage:$perPage) {
    pageInfo { hasNextPage currentPage }
    media(type:MANGA, format:NOVEL, search:$search, sort:$sort, genre_in:$genre_in, tag_in:$tag_in,
          status_in:$status_in, countryOfOrigin:$country,
          startDate_greater:$sd_gt, startDate_lesser:$sd_lt,
          averageScore_greater:$score_gt, averageScore_lesser:$score_lt,
          volumes_greater:$vol_gt, volumes_lesser:$vol_lt,
          chapters_greater:$ch_gt, chapters_lesser:$ch_lt, isAdult:$adult) {
      %s
    }
  }
}
""" % _CARD_FIELDS

_TAGS_Q = """
query { MediaTagCollection { name category isAdult isGeneralSpoiler } }
"""

_INFO_Q = """
query ($id:Int) {
  Media(id:$id, type:MANGA) {
    %s synonyms description(asHtml:false) siteUrl popularity favourites isAdult
    startDate{year month day} endDate{year month day}
    tags { name rank isMediaSpoiler category }
    staff(perPage:8, sort:RELEVANCE) { edges { role node { name { full } } } }
  }
}
""" % _CARD_FIELDS

_cache      = {}
_cache_lock = threading.Lock()
_CACHE_MAX  = 200


def _cached(key, ttl, make):
    """make() once per `ttl` seconds per key (a small in-memory cache, so paging back and forth
    and re-opening a filter does not ask AniList again; AniList allows about 90 requests a minute)."""
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and now - hit[0] < ttl:
            return hit[1]
    value = make()
    with _cache_lock:
        if len(_cache) >= _CACHE_MAX:
            for k in sorted(_cache, key=lambda k: _cache[k][0])[:_CACHE_MAX // 4]:
                del _cache[k]
        _cache[key] = (time.time(), value)
    return value


def _score(v):
    """A 0-100 score from the panel, or 0 for none."""
    try:
        v = int(v)
    except (TypeError, ValueError):
        return 0
    return v if 1 <= v <= 100 else 0


def _length(v):
    """A volume or chapter count from the panel, or 0 for none."""
    try:
        v = int(v)
    except (TypeError, ValueError):
        return 0
    return v if 1 <= v <= AL_LEN_MAX else 0


def _pair(lo, hi):
    lo, hi = _length(lo), _length(hi)
    if lo and hi and lo > hi:
        lo, hi = hi, lo
    return lo, hi


def _clean_tags(tags):
    """Tag names from the panel: strings, no oddities, no repeats, a sane number."""
    out = []
    for t in tags or ():
        t = re.sub(r"\s+", " ", str(t)).strip()
        if 0 < len(t) <= 60 and "|" not in t and t not in out:
            out.append(t)
    return tuple(out[:AL_TAG_MAX])


def _browse_card(m):
    cover = m.get("coverImage") or {}
    img = cover.get("extraLarge") or cover.get("large") or ""
    return {
        "id":        "al:%s" % m["id"],
        "anilistId": m["id"],
        "title":     _title(m),
        "cover":     img,
        "type":      _TYPE_LABEL.get(m.get("countryOfOrigin"), "NOVEL"),
        "status":    _STATUS_LABEL.get(m.get("status"), ""),
        "year":      (m.get("startDate") or {}).get("year") or 0,
        "score":     m.get("averageScore") or 0,
        "genres":    m.get("genres") or [],
        "volumes":   m.get("volumes") or 0,
        "chapters":  m.get("chapters") or 0,
    }


def browse(q="", genres=(), tags=(), country="", status=(), year=0, sort="", adult=False,
           page=1, score_min=0, score_max=0, vol_min=0, vol_max=0, ch_min=0, ch_max=0, img=None):
    """One page of AniList novels. Every argument is checked here, so a bad value from the panel
    is dropped rather than sent on. `img`, when given, turns a cover address into the one the
    panel loads (the server's image cache); it is applied after the cache, so cached pages stay plain."""
    q       = (q or "").strip()
    genres  = tuple(sorted({g for g in genres if g in AL_GENRES}))
    tags    = _clean_tags(tags)
    if isinstance(status, str):
        status = [x for x in status.split(",") if x]
    status  = tuple(sorted({x for x in status if x in AL_STATUSES}))
    country = country if country in AL_COUNTRIES else ""
    try:
        year = int(year)
    except (TypeError, ValueError):
        year = 0
    year = year if 1900 <= year <= 2100 else 0
    score_min, score_max = _score(score_min), _score(score_max)
    if score_min and score_max and score_min > score_max:
        score_min, score_max = score_max, score_min
    vol_min, vol_max = _pair(vol_min, vol_max)
    ch_min,  ch_max  = _pair(ch_min,  ch_max)
    if q:
        sort = sort if sort in AL_SORTS else "SEARCH_MATCH"
    else:
        sort = sort if sort in AL_SORTS and sort != "SEARCH_MATCH" else "TRENDING_DESC"
    try:
        page = max(1, int(page))
    except (TypeError, ValueError):
        page = 1
    adult = bool(adult)
    key = ("browse", q, genres, tags, country, status, year, score_min, score_max,
           vol_min, vol_max, ch_min, ch_max, sort, adult, page)
    data = _cached(key, TTL_BROWSE, lambda: _browse(
        q, genres, tags, country, status, year, score_min, score_max,
        vol_min, vol_max, ch_min, ch_max, sort, adult, page))
    if not img:
        return data
    return dict(data, results=[dict(r, image=img(r["cover"]) if r["cover"] else "")
                               for r in data["results"]])


def _browse(q, genres, tags, country, status, year, score_min, score_max,
            vol_min, vol_max, ch_min, ch_max, sort, adult, page):
    v = {"page": page, "perPage": AL_PER_PAGE, "sort": [sort]}
    if q:        v["search"]    = q
    if genres:   v["genre_in"]  = list(genres)
    if tags:     v["tag_in"]    = list(tags)
    if status:   v["status_in"] = list(status)
    if country:  v["country"]   = country
    if year:
        # FuzzyDateInt is YYYYMMDD; month/day 00 sit just before the first / after the last day
        v["sd_gt"] = year * 10000
        v["sd_lt"] = (year + 1) * 10000
    # AniList's *_greater / *_lesser leave the number itself out, so "7.0 and up" (70) asks for
    # greater than 69, and "up to 8.0" (80) for less than 81. The same for volumes and chapters.
    if score_min: v["score_gt"] = score_min - 1
    if score_max and score_max < 100: v["score_lt"] = score_max + 1
    if vol_min:   v["vol_gt"]   = vol_min - 1
    if vol_max:   v["vol_lt"]   = vol_max + 1
    if ch_min:    v["ch_gt"]    = ch_min - 1
    if ch_max:    v["ch_lt"]    = ch_max + 1
    if not adult:
        v["adult"] = False          # left out when asked for, which allows both
    data = _request(_BROWSE_Q, v).get("Page") or {}
    info = data.get("pageInfo") or {}
    return {
        "results":  [_browse_card(m) for m in data.get("media") or []
                     if (m.get("format") or AL_FORMAT) == AL_FORMAT],
        "hasMore":  bool(info.get("hasNextPage")),
        "nextPage": page + 1,
    }


# ── AniList's tags (the tag filter) ─────────────────────────────────────────
# A few hundred (Isekai, Villainess, Cultivation, ...), far too many to hard-code, and they get
# new ones. Asked for once and kept in al_tags.json for a week; if AniList can't be reached the
# old copy is used.

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
    rows = _request(_TAGS_Q, {}).get("MediaTagCollection") or []
    out = [{"name": t["name"], "category": t.get("category") or "", "isAdult": bool(t.get("isAdult"))}
           for t in rows if t.get("name") and not t.get("isGeneralSpoiler")]
    out.sort(key=lambda t: (t["category"], t["name"].lower()))
    return out


def tags():
    """{tags: [{name, category, isAdult}]} for the tag filter (general spoiler tags left out)."""
    def load():
        saved = _tags_read_file()
        if saved and time.time() - float(saved.get("fetchedAt") or 0) < TTL_TAGS:
            return saved["tags"]
        try:
            fresh = _tags_fetch()
        except AlError:
            if saved:                       # AniList is down: an old list beats no list
                return saved["tags"]
            raise
        try:
            os.makedirs(NOVEL_DIR, exist_ok=True)
            tmp = TAGS_FILE + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"fetchedAt": time.time(), "tags": fresh}, f)
            os.replace(tmp, TAGS_FILE)
        except OSError:
            pass
        return fresh
    return {"tags": _cached(("tags",), 3600, load)}


# ── One novel's page ────────────────────────────────────────────────────────

def _plain(raw, limit=2400):
    """AniList's description as plain paragraphs: line breaks kept, tags and entities gone."""
    s = str(raw or "")
    s = re.sub(r"(?i)<br\s*/?>", "\n", s)
    s = re.sub(r"(?i)</p\s*>", "\n\n", s)
    s = re.sub(r"<[^>]*>", "", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n[ \t]+", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s).strip()
    return s if len(s) <= limit else s[:limit].rsplit(" ", 1)[0].rstrip(".,;: ") + "…"


def _date(d):
    d = d or {}
    y, mo, dy = d.get("year"), d.get("month"), d.get("day")
    if not y:
        return ""
    if mo and dy:
        return "%04d-%02d-%02d" % (y, mo, dy)
    if mo:
        return "%04d-%02d" % (y, mo)
    return str(y)


def _names_for_search(m):
    """The names a source might know the novel by, the shown title first, no repeats."""
    out = []
    for n in [_title(m)] + _names(m):
        n = str(n or "").strip()
        if n and n.lower() not in [x.lower() for x in out]:
            out.append(n)
    return out[:6]


def info(aid):
    """What the Discover page shows for one AniList novel. A title that is not a NOVEL is refused,
    like everywhere else in this module."""
    mid = _media_id(aid)

    def load():
        media = _request(_INFO_Q, {"id": mid}).get("Media")
        if not media:
            raise AlError("AniList has no title with that id", 404)
        if media.get("format") != AL_FORMAT:
            raise AlError("That AniList title is not a novel", 400)
        card = _browse_card(media)
        card["image"] = card["cover"]
        people = []
        for e in ((media.get("staff") or {}).get("edges") or []):
            name = ((e.get("node") or {}).get("name") or {}).get("full")
            role = e.get("role") or ""
            if name and not any(p["name"] == name for p in people):
                people.append({"name": name, "role": role})
        tags_ = sorted([t for t in media.get("tags") or [] if not t.get("isMediaSpoiler") and t.get("name")],
                       key=lambda t: -(t.get("rank") or 0))
        card.update({
            "names":      _names_for_search(media),
            "description": _plain(media.get("description")),
            "popularity": media.get("popularity") or 0,
            "favourites": media.get("favourites") or 0,
            "adult":      bool(media.get("isAdult")),
            "start":      _date(media.get("startDate")),
            "end":        _date(media.get("endDate")),
            "tags":       [t["name"] for t in tags_[:10]],
            "people":     people[:6],
            "siteUrl":    media.get("siteUrl") or "",
        })
        return card
    return _cached(("info", mid), TTL_INFO, load)


# ── Which AniList novel a novel is ──────────────────────────────────────────

def _norm(s):
    s = unicodedata.normalize("NFKD", str(s or "")).lower()
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9\u3040-\u30ff\u4e00-\u9fff]+", " ", s).strip()


def similarity(a, b):
    a, b = _norm(a), _norm(b)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def _names(m):
    t = m.get("title") or {}
    return [x for x in [t.get("english"), t.get("romaji"), t.get("native")] + list(m.get("synonyms") or []) if x]


def best_match(title, media):
    """(media, score) for the closest of `media` to `title`, or (None, 0)."""
    best, score = None, 0.0
    for m in media:
        s = max([similarity(title, n) for n in _names(m)] or [0.0])
        if s > score:
            best, score = m, s
    return best, score


_match_lock = threading.Lock()
_no_match   = set()                  # titles that found nothing this session (do not ask again)


def _matches_read():
    try:
        with open(MATCH_FILE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _matches_write(data):
    os.makedirs(os.path.dirname(MATCH_FILE), exist_ok=True)
    tmp = MATCH_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, MATCH_FILE)


def _stored(novel_id):
    e = _matches_read().get(novel_id)
    if isinstance(e, dict) and isinstance(e.get("anilistId"), int) and e["anilistId"] > 0:
        return {"anilistId": e["anilistId"], "title": str(e.get("title") or ""),
                "manual": e.get("manual") is True}
    return None


def match_get(novel_id, title):
    """{match: {anilistId, title, manual} | None}. A match picked by hand is kept as it is; else
    the closest AniList novel is taken if its name is close enough, and kept."""
    if not novel_id:
        raise AlError("missing novelId", 400)
    with _match_lock:
        found = _stored(novel_id)
    if found:
        return {"match": found}
    key = (novel_id, _norm(title))
    if not title or key in _no_match:
        return {"match": None}
    media = (_request(_SEARCH_Q, {"q": title}).get("Page") or {}).get("media") or []
    media = [m for m in media if (m.get("format") or AL_FORMAT) == AL_FORMAT]
    best, score = best_match(title, media)
    if not best or score < MATCH_MIN:
        _no_match.add(key)
        return {"match": None}
    found = {"anilistId": best["id"], "title": _title(best), "manual": False}
    with _match_lock:
        data = _matches_read()
        if not _stored(novel_id):                   # a pick made meanwhile wins
            data[novel_id] = found
            _matches_write(data)
    return {"match": found}


def match_set(novel_id, anilist_id, title=""):
    if not novel_id:
        raise AlError("missing novelId", 400)
    aid = _media_id(anilist_id)
    # a manga is refused here, so the pick can only ever be a novel
    media = _novel_media(aid)
    with _match_lock:
        data = _matches_read()
        data[novel_id] = {"anilistId": aid, "title": title or _title(media), "manual": True}
        _matches_write(data)
    _no_match.clear()
    return {"match": _stored(novel_id)}


def match_clear(novel_id):
    if not novel_id:
        raise AlError("missing novelId", 400)
    with _match_lock:
        data = _matches_read()
        if novel_id in data:
            del data[novel_id]
            _matches_write(data)
    # forget "found nothing" too, so the next open looks again
    _no_match.clear()
    return {"match": None}


# ── Tracking ────────────────────────────────────────────────────────────────

_ENTRY_FIELDS = "id status score score100:score(format:POINT_100) progress progressVolumes"

_TRACK_Q = """
query ($id:Int) {
  Media(id:$id, type:MANGA) { id format chapters volumes siteUrl mediaListEntry { %s } }
}
""" % _ENTRY_FIELDS

_NOVEL_Q = """
query ($id:Int) {
  Media(id:$id, type:MANGA) { %s }
}
""" % _MEDIA_FIELDS


def _media_id(aid):
    s = str(aid if aid is not None else "")
    if not s.isdigit() or int(s) <= 0:
        raise AlError("missing or bad anilistId", 400)
    return int(s)


def _int(v, name):
    try:
        n = int(v)
    except (TypeError, ValueError):
        raise AlError("%s must be a whole number" % name, 400)
    if n < 0 or n > AL_TRACK_MAX:
        raise AlError("%s is out of range" % name, 400)
    return n


def _novel_media(aid):
    media = _request(_NOVEL_Q, {"id": aid}).get("Media")
    if not media:
        raise AlError("AniList has no title with that id", 404)
    if media.get("format") != AL_FORMAT:
        raise AlError("That AniList title is not a novel", 400)
    return media


def _view(media):
    media = media or {}
    e = media.get("mediaListEntry")
    return {
        "anilistId": media.get("id") or 0,
        "chapters":  media.get("chapters") or 0,
        "volumes":   media.get("volumes") or 0,
        "siteUrl":   media.get("siteUrl") or "",
        "entry": ({
            "status":          e.get("status") or "",
            "score":           e.get("score") or 0,
            "score100":        e.get("score100") or 0,
            "progress":        e.get("progress") or 0,
            "progressVolumes": e.get("progressVolumes") or 0,
        } if e else None),
    }


def track_info(aid):
    mid = _media_id(aid)
    media = _request(_TRACK_Q, {"id": mid}, _token()).get("Media")
    if not media:
        raise AlError("AniList has no title with that id", 404)
    if media.get("format") != AL_FORMAT:
        raise AlError("That AniList title is not a novel, so this reader does not track it", 400)
    return _view(media)


def _save(mid, fields):
    """SaveMediaListEntry with only the fields given (a field left out is left alone on AniList)."""
    types = {"status": "MediaListStatus", "progress": "Int", "progressVolumes": "Int"}
    names = [k for k in types if k in fields]
    decl  = "".join(", $%s:%s" % (k, types[k]) for k in names)
    args  = "".join(", %s:$%s" % (k, k) for k in names)
    q = ("mutation ($mediaId:Int%s) { SaveMediaListEntry(mediaId:$mediaId%s) { %s } }"
         % (decl, args, _ENTRY_FIELDS))
    data = _request(q, dict({"mediaId": mid}, **{k: fields[k] for k in names}), _token())
    return data.get("SaveMediaListEntry") or {}


def track_progress(aid, progress, volumes=0):
    """Tell AniList how far the novel has been read. Never lowers what it has."""
    mid      = _media_id(aid)
    progress = _int(progress or 0, "progress")
    volumes  = _int(volumes or 0, "volumes")
    cur      = track_info(mid)                 # also refuses a title that is not a novel
    entry    = cur["entry"] or {}
    fields   = {}
    if progress > (entry.get("progress") or 0):
        fields["progress"] = progress
    if volumes > (entry.get("progressVolumes") or 0):
        fields["progressVolumes"] = volumes
    new_progress = fields.get("progress", entry.get("progress") or 0)
    st = entry.get("status") or ""
    if progress > 0 or volumes > 0:
        if st in ("", "PLANNING", "PAUSED", "DROPPED"):
            fields["status"] = "CURRENT"
        if cur["chapters"] and new_progress >= cur["chapters"] and st not in ("COMPLETED", "REPEATING"):
            fields["status"] = "COMPLETED"
    if not fields:
        cur["changed"] = False
        return cur
    saved = _save(mid, fields)
    cur["entry"] = {
        "status":          saved.get("status") or fields.get("status") or st,
        "score":           saved.get("score", entry.get("score") or 0) or 0,
        "score100":        saved.get("score100", entry.get("score100") or 0) or 0,
        "progress":        saved.get("progress", new_progress) or 0,
        "progressVolumes": saved.get("progressVolumes",
                                     fields.get("progressVolumes", entry.get("progressVolumes") or 0)) or 0,
    }
    cur["changed"] = True
    return cur


def track_set(aid, status=None, progress=None, volumes=None):
    """The user's own choice, from the track sheet: exactly these values, lower or not."""
    mid    = _media_id(aid)
    fields = {}
    if status not in (None, ""):
        if status not in AL_LIST_STATUSES:
            raise AlError("unknown status", 400)
        fields["status"] = status
    if progress is not None:
        fields["progress"] = _int(progress, "progress")
    if volumes is not None:
        fields["progressVolumes"] = _int(volumes, "volumes")
    if not fields:
        raise AlError("nothing to set", 400)
    track_info(mid)                            # a title that is not a novel is refused first
    _save(mid, fields)
    out = track_info(mid)
    out["changed"] = True
    return out
