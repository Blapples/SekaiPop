#!/usr/bin/env python3
# Ported from dhrruvsharma/shell (GPL-3.0-or-later), paths changed for SekaiPop.
"""
Novel backend server for QuickShell ServiceNovel.
Serves clean JSON on http://127.0.0.1:5151

Endpoints (unchanged from original):
  GET  /search?q=<query>&genre=<genre>&status=<All|Ongoing|Completed>&page=<n>
  GET  /info?id=<novel-id>
  GET  /chapter?id=<chapter-id>
  GET  /hot
  GET  /latest?page=<n>
  GET  /image?url=<encoded-url>
  GET  /favorites
  POST /favorites/add         body: {id, title, imageUrl}
  POST /favorites/remove      body: {id}
  POST /favorites/mark-seen   body: {id, chapterId}
  GET  /favorites/check
  GET  /dl/list
  GET  /dl/progress?chapterId=<id>
  GET  /dl/chapter?chapterId=<id>
  POST /dl/start              body: {novelId, chapterId, chapterNum, chapterTitle, novelTitle, rawCoverUrl}
  POST /dl/delete             body: {chapterId}
  GET  /health

AniList tracking (novels only; the login is the manga reader's, see anilist.py):
  GET  /al/status                     → {loggedIn, expired, viewer}
  GET  /al/match?novelId=&title=      → {match: {anilistId, title, manual} | null}
  GET  /al/search?q=<text>            → [{anilistId, title, cover, year, chapters, volumes, status, siteUrl}]
  GET  /al/browse?q=&genres=a,b&tags=a|b&country=&status=a,b&year=&score_min=&score_max=
                  &vol_min=&vol_max=&ch_min=&ch_max=&sort=&adult=0&page=1
                                      → {results, hasMore, nextPage}  (Discover: AniList novels, no login)
  GET  /al/tags                       → {tags: [{name, category, isAdult}]}  (for the tag filter)
  GET  /al/info?id=<anilistId>        → one novel's page (description, tags, names to search a source by)
  POST /al/match/set    body: {novelId, anilistId, title}
  POST /al/match/clear  body: {novelId}
  GET  /al/track?id=<anilistId>       → {anilistId, chapters, volumes, siteUrl, entry}
  POST /al/track/progress  body: {anilistId, progress, volumes}   (only ever goes up)
  POST /al/track/set       body: {anilistId, status, progress, volumes}

Provider-switching endpoints (new):
  GET  /provider/list         → [{name, label}, ...]
  GET  /provider/active       → {name, label}
  POST /provider/switch       body: {provider: "lnreader"}

LNReader sources (the plugins the reader browses):
  GET  /lnreader/status       → {node: {state, message}, repo, active, sources}
  GET  /lnreader/sources      → {active, sources: [{id, name, lang, site, version, iconUrl}]}
  GET  /lnreader/catalog?refresh=1   → {repo, total, plugins: [... installed, update]}
  POST /lnreader/install      body: {id}
  POST /lnreader/uninstall    body: {id}
  POST /lnreader/select       body: {id}
  POST /lnreader/repo         body: {url}   ("" goes back to the official list); the one-address call
  GET  /lnreader/repos        → {repos: [{id, name, official}], suggested: [{name, url}]}
  POST /lnreader/repos        body: {add: url} and/or {remove: id}   ("official" is the official list)
  POST /lnreader/update-all   → {ok, updated, failed: [{id, error}]}
  GET  /hot?page=<n>          → {results, hasMore, nextPage} (without page: the plain list, as before)

All novel/chapter IDs crossing the HTTP boundary are PREFIXED:
  "freewebnovel:novel/some-slug"
  "freewebnovel:novel/some-slug/chapter-5"
The providers package handles stripping/adding prefixes transparently.
"""

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs, quote, unquote

import anilist
import providers
import storage
from providers.lnreader import LNReaderProvider

PORT = 5151


# ── Image byte cache ───────────────────────────────────────────────────────

_img_cache:     dict         = {}
_img_cache_lock              = threading.Lock()
_img_cache_max               = 400
_img_sem                     = threading.Semaphore(8)


def _img_get(url):
    with _img_cache_lock:
        return _img_cache.get(url)


def _img_put(url, body, ctype):
    with _img_cache_lock:
        if len(_img_cache) >= _img_cache_max:
            _img_cache.pop(next(iter(_img_cache)))
        _img_cache[url] = (body, ctype)


def proxy_url(img_url: str) -> str:
    return f"http://127.0.0.1:{PORT}/image?url={quote(img_url, safe='')}"


# ── Provider-aware ID helpers ──────────────────────────────────────────────

def _get_info(prefixed_id: str) -> dict:
    """Fetch novel info using whichever provider owns this prefixed ID."""
    pname, raw_id = providers.strip_prefix(prefixed_id)
    p             = providers.provider_for(prefixed_id)
    data          = p.info(raw_id)
    # Re-prefix every chapter id before returning to client
    data["id"]       = providers.prefix_id(data["id"], pname)
    data["chapters"] = [
        {**c, "id": providers.prefix_id(c["id"], pname)}
        for c in data["chapters"]
    ]
    return data


def _get_chapter(prefixed_id: str) -> dict:
    pname, raw_id = providers.strip_prefix(prefixed_id)
    p             = providers.provider_for(prefixed_id)
    data          = p.chapter(raw_id)
    # Re-prefix prev/next so the client can pass them straight back
    data["id"]     = providers.prefix_id(data["id"], pname)
    data["prevId"] = providers.prefix_id(data["prevId"], pname) if data.get("prevId") else ""
    data["nextId"] = providers.prefix_id(data["nextId"], pname) if data.get("nextId") else ""
    return data


def _prefix_results(results: list, pname: str) -> list:
    """Add provider prefix to every id in a list of novel cards."""
    return [{**r, "id": providers.prefix_id(r["id"], pname)} for r in results]


# ── HTTP Server ────────────────────────────────────────────────────────────

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads      = True
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[novel-server] {fmt % args}")

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type",   "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, msg, status=500):
        self._json({"error": msg}, status)

    def _local_only(self):
        """The AniList endpoints answer the panel only: they act as the logged-in user, so a
        request that names another host (DNS rebinding) or comes from a web page (an Origin
        other than this server) is refused."""
        host   = (self.headers.get("Host") or "").rsplit(":", 1)[0].lower()
        origin = self.headers.get("Origin")
        ok = host in ("127.0.0.1", "localhost") and (
            not origin or origin in (f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"))
        if not ok:
            body = json.dumps({"error": "not allowed"}).encode()
            self.send_response(403)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        return ok

    def _send_image(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type",   ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control",  "public, max-age=86400")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _proxy_image(self, img_url: str):
        cached = _img_get(img_url)
        if cached:
            self._send_image(*cached)
            return
        with _img_sem:
            body, ctype = providers.get().fetch_image(img_url)
        _img_put(img_url, body, ctype)
        self._send_image(body, ctype)

    # ── GET ────────────────────────────────────────────────────────────────

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
            p   = parsed.path
            prv = providers.get()           # active provider
            pn  = prv.name                  # its name, for prefixing

            # ── Provider management ──────────────────────────────────────
            if p == "/provider/list":
                self._json(providers.list_all())

            elif p == "/provider/active":
                self._json({"name": prv.name, "label": prv.label})

            # ── Novel browsing ───────────────────────────────────────────
            elif p == "/hot":
                if "page" in qs:
                    page = int(param("page", "1"))
                    if hasattr(prv, "hot_page"):
                        data = prv.hot_page(page)
                    else:
                        data = {"results": prv.hot() if page == 1 else [],
                                "hasMore": False, "nextPage": page + 1}
                    data["results"] = _prefix_results(data["results"], pn)
                    self._json(data)
                else:
                    self._json(_prefix_results(prv.hot(), pn))

            # ── LNReader sources ─────────────────────────────────────────
            elif p == "/lnreader/status":
                self._json(LNReaderProvider().status())

            elif p == "/lnreader/sources":
                self._json(LNReaderProvider().sources())

            elif p == "/lnreader/catalog":
                self._json(LNReaderProvider().catalog(param("refresh") == "1"))

            elif p == "/lnreader/repos":
                self._json(LNReaderProvider().repos())

            elif p == "/latest":
                data = prv.latest(int(param("page", "1")))
                data["results"] = _prefix_results(data["results"], pn)
                self._json(data)

            elif p == "/search":
                q = param("q")
                if not q:
                    return self._error("missing q", 400)
                data = prv.search(
                    q,
                    param("genre") or None,
                    param("status", "All"),
                    int(param("page", "1")),
                )
                data["results"] = _prefix_results(data["results"], pn)
                self._json(data)

            elif p == "/info":
                nid = param("id")
                if not nid:
                    return self._error("missing id", 400)
                self._json(_get_info(nid))

            elif p == "/chapter":
                cid = param("id")
                if not cid:
                    return self._error("missing id", 400)
                # Offline-first
                offline = storage.dl_chapter_offline(cid)
                if offline:
                    self._json(offline)
                else:
                    self._json(_get_chapter(cid))

            elif p == "/image":
                img_url = unquote(param("url"))
                if not img_url:
                    return self._error("missing url", 400)
                self._proxy_image(img_url)

            # ── Favorites ────────────────────────────────────────────────
            elif p == "/favorites":
                self._json(storage.fav_list(proxy_url))

            elif p == "/favorites/check":
                self._json(storage.fav_check(_get_info))

            # ── Downloads ────────────────────────────────────────────────
            elif p == "/dl/list":
                self._json(storage.dl_list(proxy_url))

            elif p == "/dl/progress":
                cid = param("chapterId")
                if not cid:
                    return self._error("missing chapterId", 400)
                self._json(storage.dl_progress(cid))

            elif p == "/dl/chapter":
                cid = param("chapterId")
                if not cid:
                    return self._error("missing chapterId", 400)
                data = storage.dl_chapter_offline(cid)
                if data is None:
                    return self._error("not downloaded", 404)
                self._json(data)

            # ── AniList (novels only) ────────────────────────────────────
            elif p.startswith("/al/"):
                if not self._local_only():
                    return
                if p == "/al/status":
                    self._json(anilist.status())
                elif p == "/al/match":
                    self._json(anilist.match_get(param("novelId"), param("title")))
                elif p == "/al/search":
                    self._json(anilist.search(param("q")))
                elif p == "/al/browse":
                    def _int(name):
                        v = param(name, "0")
                        return int(v) if v.lstrip("-").isdigit() else 0
                    self._json(anilist.browse(
                        q=param("q"),
                        genres=[g for g in param("genres").split(",") if g],
                        tags=[t for t in param("tags").split("|") if t],
                        country=param("country"), status=param("status"),
                        year=_int("year"), sort=param("sort"), adult=param("adult") == "1",
                        page=max(1, _int("page")),
                        score_min=_int("score_min"), score_max=_int("score_max"),
                        vol_min=_int("vol_min"), vol_max=_int("vol_max"),
                        ch_min=_int("ch_min"), ch_max=_int("ch_max"),
                        img=proxy_url))
                elif p == "/al/tags":
                    self._json(anilist.tags())
                elif p == "/al/info":
                    data = anilist.info(param("id"))
                    self._json(dict(data, image=proxy_url(data["cover"]) if data.get("cover") else ""))
                elif p == "/al/track":
                    self._json(anilist.track_info(param("id")))
                else:
                    self._error("not found", 404)

            elif p == "/health":
                self._json({"ok": True, "provider": pn})

            else:
                self._error("not found", 404)

        except (BrokenPipeError, ConnectionResetError):
            pass
        except anilist.AlError as e:
            self._error(str(e), e.status)
        except ValueError as e:
            self._error(str(e), 400)
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._error(str(e))

    # ── POST ───────────────────────────────────────────────────────────────

    def do_POST(self):
        parsed = urlparse(self.path)
        try:
            length = int(self.headers.get("Content-Length", 0))
            body   = json.loads(self.rfile.read(length)) if length else {}
        except Exception:
            return self._error("bad request body", 400)

        try:
            p = parsed.path

            # ── Provider switching ───────────────────────────────────────
            if p == "/provider/switch":
                name = body.get("provider", "")
                if not name:
                    return self._error("missing provider", 400)
                providers.switch(name)
                self._json({"ok": True, "active": name})

            # ── LNReader sources ─────────────────────────────────────────
            elif p == "/lnreader/install":
                self._json(LNReaderProvider().install(body.get("id", "")))

            elif p == "/lnreader/uninstall":
                self._json(LNReaderProvider().uninstall(body.get("id", "")))

            elif p == "/lnreader/select":
                self._json(LNReaderProvider().select(body.get("id", "")))

            elif p == "/lnreader/repo":
                self._json(LNReaderProvider().set_repo(body.get("url", "")))

            elif p == "/lnreader/repos":
                self._json(LNReaderProvider().change_repos(body.get("add", ""), body.get("remove", "")))

            elif p == "/lnreader/update-all":
                self._json(LNReaderProvider().update_all())

            # ── Favorites ────────────────────────────────────────────────
            elif p == "/favorites/add":
                nid = body.get("id", "")
                if not nid:
                    return self._error("missing id", 400)
                self._json(storage.fav_add(nid, body.get("title", ""), body.get("imageUrl", "")))

            elif p == "/favorites/remove":
                nid = body.get("id", "")
                if not nid:
                    return self._error("missing id", 400)
                self._json(storage.fav_remove(nid))

            elif p == "/favorites/mark-seen":
                nid = body.get("id", "")
                if not nid:
                    return self._error("missing id", 400)
                self._json(storage.fav_mark_seen(nid, body.get("chapterId", "")))

            # ── Downloads ────────────────────────────────────────────────
            elif p == "/dl/start":
                nid = body.get("novelId", "")
                cid = body.get("chapterId", "")
                if not (nid and cid):
                    return self._error("missing novelId or chapterId", 400)
                self._json(storage.dl_start(
                    nid, cid,
                    body.get("chapterNum", ""),
                    body.get("chapterTitle", ""),
                    body.get("novelTitle", ""),
                    body.get("rawCoverUrl", ""),
                    _get_chapter,          # provider-aware fetch function
                ))

            elif p == "/dl/delete":
                cid = body.get("chapterId", "")
                if not cid:
                    return self._error("missing chapterId", 400)
                self._json(storage.dl_remove(cid))

            # ── AniList (novels only) ────────────────────────────────────
            elif p.startswith("/al/"):
                if not self._local_only():
                    return
                if p == "/al/match/set":
                    self._json(anilist.match_set(body.get("novelId", ""), body.get("anilistId"),
                                                 body.get("title", "")))
                elif p == "/al/match/clear":
                    self._json(anilist.match_clear(body.get("novelId", "")))
                elif p == "/al/track/progress":
                    self._json(anilist.track_progress(body.get("anilistId"), body.get("progress"),
                                                      body.get("volumes")))
                elif p == "/al/track/set":
                    self._json(anilist.track_set(body.get("anilistId"), body.get("status"),
                                                 body.get("progress"), body.get("volumes")))
                else:
                    self._error("not found", 404)

            else:
                self._error("not found", 404)

        except (BrokenPipeError, ConnectionResetError):
            pass
        except anilist.AlError as e:
            self._error(str(e), e.status)
        except ValueError as e:
            self._error(str(e), 400)
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._error(str(e))


# ── Entry point ────────────────────────────────────────────────────────────

def exit_with_parent():
    """Quit once the shell that started us is gone: a killed Quickshell
    leaves its children running, and a stale server would hold the port."""
    parent = os.getppid()

    def watch():
        while os.getppid() == parent:
            time.sleep(2)
        os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def run():
    exit_with_parent()
    LNReaderProvider().bootstrap()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[novel-server] Listening on http://127.0.0.1:{PORT}")
    print(f"[novel-server] Active provider: {providers.active_name()}")
    server.serve_forever()


if __name__ == "__main__":
    run()