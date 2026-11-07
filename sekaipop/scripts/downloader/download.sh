#!/usr/bin/env bash

# Helper for DownloaderService.qml: downloads ONE link and tells the shell how it is going.
#
#   download.sh <engine> <mode> <quality> <audioFormat> <folder> <url>
#
#   engine       auto | ytdlp | gallerydl | cobalt | fetch
#                auto   tries what is installed, in this order, until one works:
#                         yt-dlp        videos and sound, from a very long list of sites
#                         gallery-dl    pictures and picture posts (Twitter / X, Instagram, Pinterest ...)
#                                       (only for "video", not for sound only or mute)
#                         cobalt        the instance named in SEKAI_COBALT_URL, if there is one
#                the others use only that one. fetch saves the items chosen in the picker
#                (SEKAI_ITEMS, see below).
#   mode         video | audio | mute
#   quality      max | 2160 | 1440 | 1080 | 720 | 480 | 360
#   audioFormat  mp3 | opus | ogg | wav | m4a | flac | best     (cobalt knows: best mp3 ogg wav opus)
#   folder       where the file goes ("" = your Downloads folder)
#   url          the link
#
# Everything else comes in the environment, never on the command line (a command line can be read
# by every program on the machine, and some of this is private):
#
#   SEKAI_COBALT_URL    the cobalt instance's address, e.g. https://cobalt.example.org
#   SEKAI_COBALT_KEY    optional: sent as "Authorization: Api-Key <key>"
#   SEKAI_COOKIES       a browser whose login to use (firefox, chrome, chromium, brave, edge, vivaldi, opera)
#   SEKAI_COOKIES_FILE  or a cookies.txt file (wins over the browser)
#   SEKAI_SUBS          a language to save the subtitles in ("en"); empty = none
#   SEKAI_NAMES         file names: basic | pretty | classic | nerdy
#   SEKAI_PICK          1 = a post with several items is not saved yet: its items are listed so the
#                       shell can ask which ones (then it calls us again with engine "fetch")
#   SEKAI_ITEMS         for "fetch": one item per line, "<type><TAB><address>"
#
# Everything this prints is one line, so the shell can read it as it comes:
#
#   SEKAI|engine|<ytdlp | gallerydl | cobalt>          which one is working now
#   SEKAI|title|<what it is called>
#   SEKAI|prog|<percent>|<speed>|<time left>           (a field that is not known is empty)
#   SEKAI|item|<type><TAB><address><TAB><picture>      one item of a post (only with SEKAI_PICK=1)
#   SEKAI|choose|<how many>                            the items above are for the user to choose from
#   SEKAI|file|<the finished file>
#   SEKAI|err|<what went wrong, in one line>
#   SEKAI|done                                         (last line of a download that worked)
#
# Stopping it (SIGTERM) stops the program it started too. Nothing else is written anywhere
# except the file itself (and the little .part file of a download that was cut short, which
# yt-dlp carries on from if you try the same link again).

engine="$1"
mode="$2"
quality="$3"
afmt="$4"
folder="$5"
url="$6"

TAB="$(printf '\t')"

say() { printf 'SEKAI|%s\n' "$*"; }
fail() { say "err|$*"; exit 1; }

[ -n "$url" ] || fail "There is no link to download."

# Where it goes.
if [ -z "$folder" ]; then
    folder="$(xdg-user-dir DOWNLOAD 2>/dev/null)"
    { [ -n "$folder" ] && [ "$folder" != "$HOME" ]; } || folder="$HOME/Downloads"
fi
case "$folder" in
    "~") folder="$HOME" ;;
    "~/"*) folder="$HOME/${folder#\~/}" ;;
esac
mkdir -p "$folder" 2>/dev/null || fail "Can't make the folder $folder."
[ -w "$folder" ] || fail "Can't write in $folder."

child=""
cleanup() {
    [ -n "$child" ] && kill "$child" 2>/dev/null
    rm -f "$tmpdir"/* 2>/dev/null
    [ -n "$tmpdir" ] && rmdir "$tmpdir" 2>/dev/null
}
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/sekai-dl.XXXXXX")" || fail "Can't make a temporary folder."
trap 'exit 143' TERM INT
trap cleanup EXIT

# What went wrong in each engine that was tried, in order (see pick_error), and whether the run
# ended by asking the user which items to save.
errs=()
note_err() { errs+=("$*"); }
chose=0
last_file=""

# The login to use: a cookies.txt file, or a browser's own.
cookie_args=()
if [ -n "$SEKAI_COOKIES_FILE" ]; then
    f="$SEKAI_COOKIES_FILE"
    case "$f" in "~/"*) f="$HOME/${f#\~/}" ;; esac
    cookie_args=(--cookies "$f")
elif [ -n "$SEKAI_COOKIES" ]; then
    cookie_args=(--cookies-from-browser "$SEKAI_COOKIES")
fi

# A name that does not exist yet in the folder: "a.mp4", then "a (1).mp4", "a (2).mp4" ...
free_path() {
    local name="$1" base ext n=1 p
    name="${name##*/}"
    name="$(printf '%s' "$name" | tr -d '\000-\037' | sed 's/^\.*//')"
    [ -n "$name" ] || name="download"
    p="$folder/$name"
    base="${name%.*}"; ext=""
    [ "$base" != "$name" ] && ext=".${name##*.}"
    while [ -e "$p" ]; do
        p="$folder/$base ($n)$ext"
        n=$((n + 1))
    done
    printf '%s' "$p"
}

# ---------------------------------------------------------------------------------------
# yt-dlp: runs on this machine, no server in between.
# ---------------------------------------------------------------------------------------
run_ytdlp() {
    if ! command -v yt-dlp >/dev/null 2>&1; then
        note_err "yt-dlp is not installed (pacman -S yt-dlp)."
        return 1
    fi
    say "engine|ytdlp"

    local tpl
    case "$SEKAI_NAMES" in
        pretty) tpl='%(title).100B (%(extractor)s).%(ext)s' ;;
        classic) tpl='%(extractor)s_%(id)s.%(ext)s' ;;
        nerdy) tpl='%(title).90B (%(height&{}p, |)s%(extractor)s, %(id)s).%(ext)s' ;;
        *) tpl='%(title).120B.%(ext)s' ;;
    esac

    local args=(--newline --progress --no-playlist --no-warnings --no-colors --no-simulate
        --paths "$folder" --output "$tpl" --trim-filenames 150 --windows-filenames
        --progress-template "download:SEKAI|prog|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"
        --print "before_dl:SEKAI|title|%(title)s"
        --print "after_move:SEKAI|file|%(filepath)s")
    args+=("${cookie_args[@]}")

    local h=""
    case "$quality" in
        2160|1440|1080|720|480|360) h="$quality" ;;
    esac

    case "$mode" in
        audio)
            if ! command -v ffmpeg >/dev/null 2>&1; then
                note_err "ffmpeg is needed to save only the sound (pacman -S ffmpeg)."
                return 1
            fi
            local f="$afmt"
            case "$f" in mp3|opus|vorbis|wav|m4a|flac|aac|best) ;; ogg) f="vorbis" ;; *) f="mp3" ;; esac
            args+=(-f "ba/b" -x --audio-format "$f" --audio-quality 0 --embed-metadata)
            ;;
        mute)
            if [ -n "$h" ]; then
                args+=(-f "bv*[height<=?$h]/bv*/b[height<=?$h]/b")
            else
                args+=(-f "bv*/b")
            fi
            ;;
        *)
            # The h264 / aac pair first (plays everywhere), the best there is if there is none.
            if [ -n "$h" ]; then
                args+=(-f "bv*[height<=?$h]+ba/b[height<=?$h]/bv*+ba/b" -S "vcodec:h264,res,acodec:aac")
            else
                args+=(-f "bv*+ba/b" -S "res,vcodec:h264,acodec:aac")
            fi
            args+=(--merge-output-format "mp4/mkv")
            ;;
    esac

    # Subtitles: saved inside the video when ffmpeg can do it, as a file beside it when not.
    if [ -n "$SEKAI_SUBS" ] && [ "$mode" != "audio" ]; then
        args+=(--write-subs --write-auto-subs --sub-langs "${SEKAI_SUBS}.*,${SEKAI_SUBS}" --convert-subs srt)
        command -v ffmpeg >/dev/null 2>&1 && [ "$mode" = "video" ] && args+=(--embed-subs)
    fi

    local errf="$tmpdir/err-ytdlp"
    yt-dlp "${args[@]}" -- "$url" 2>"$errf" &
    child=$!
    wait "$child"
    local rc=$?
    child=""
    if [ "$rc" -ne 0 ]; then
        local e
        e="$(grep -m1 '^ERROR' "$errf" 2>/dev/null | sed 's/^ERROR: *//; s/\[[a-zA-Z0-9:_ -]*\] *//' | tr -d '\r' | cut -c1-200)"
        [ -n "$e" ] || e="yt-dlp stopped with code $rc."
        note_err "$e"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------------------
# gallery-dl: pictures and picture posts (and some videos), from a long list of sites.
# ---------------------------------------------------------------------------------------

# "type<TAB>address" lines for the picker, from a list of addresses.
item_type() {
    case "$1" in
        ytdl:*|m3u8:*) echo video ;;
        *) local g="${1%%\?*}"; g="${g##*.}"
           case "$g" in mp4|webm|mov|m4v|mkv) echo video ;; gif) echo gif ;; *) echo photo ;; esac ;;
    esac
}

run_gallerydl() {
    if ! command -v gallery-dl >/dev/null 2>&1; then
        note_err "gallery-dl is not installed (pacman -S gallery-dl)."
        return 1
    fi
    say "engine|gallerydl"
    local errf="$tmpdir/err-gdl" outf="$tmpdir/out-gdl" rc

    # Asked to let the user choose: list what is there first; only a post with several items asks.
    if [ "$SEKAI_PICK" = "1" ]; then
        gallery-dl --get-urls "${cookie_args[@]}" -- "$url" >"$outf" 2>"$errf" &
        child=$!
        wait "$child"; rc=$?
        child=""
        local list n
        list="$(grep -v '^\s*$' "$outf" | grep -v '^|' | head -n 60)"
        n="$(printf '%s\n' "$list" | grep -c .)"
        if [ "$rc" -eq 0 ] && [ "$n" -gt 1 ]; then
            local u t
            while IFS= read -r u; do
                t="$(item_type "$u")"
                if [ "$t" = "photo" ]; then
                    say "item|$t$TAB$u$TAB$u"
                else
                    say "item|$t$TAB$u$TAB"
                fi
            done <<<"$list"
            say "choose|$n"
            chose=1
            return 0
        fi
        # One item, or nothing listed: the plain download below says what is wrong.
    fi

    gallery-dl --no-mtime -D "$folder" "${cookie_args[@]}" -- "$url" >"$outf" 2>"$errf" &
    child=$!
    say "prog|||"
    local seen=0 count now line
    while kill -0 "$child" 2>/dev/null; do
        now="$(grep -c '^#\? \?/' "$outf" 2>/dev/null)"
        if [ "${now:-0}" != "$seen" ]; then
            seen="$now"
            say "title|$seen file$([ "$seen" = 1 ] || echo s)"
        fi
        sleep 0.4
    done
    wait "$child"; rc=$?
    child=""
    count=0
    while IFS= read -r line; do
        line="${line#\# }"
        case "$line" in
            /*) count=$((count + 1)); last_file="$line" ;;
        esac
    done <"$outf"
    if [ "$count" -gt 0 ]; then
        say "title|$count file$([ "$count" = 1 ] || echo s)"
        say "file|$last_file"
        return 0
    fi
    local e
    e="$(grep -m1 -i 'error' "$errf" 2>/dev/null | sed 's/^\[[a-zA-Z0-9:_ -]*\]\(\[[a-z]*\]\)\? *//' | tr -d '\r' | cut -c1-200)"
    [ -n "$e" ] || e="gallery-dl found nothing to save there."
    note_err "$e"
    return 1
}

# ---------------------------------------------------------------------------------------
# cobalt: asks an instance for the file, then fetches it.
# ---------------------------------------------------------------------------------------
cobalt_message() {
    # The error codes cobalt gives, in words.
    case "$1" in
        *auth*) echo "This cobalt instance wants a key or a sign-in. Put its API key in Settings > Desktop > Downloader." ;;
        *content.video.unavailable*|*content.post.unavailable*) echo "That link is not available (private, removed, or not for your country)." ;;
        *content.too_long*) echo "That is longer than this instance allows." ;;
        *link.unsupported*|*link.invalid*|*service.unsupported*) echo "This instance can't save that link." ;;
        *rate_exceeded*) echo "Too many requests: wait a little and try again." ;;
        *fetch.empty*|*fetch.fail*|*fetch.critical*|*fetch.short_link*) echo "The instance could not read that link ($1)." ;;
        *) echo "The instance said: $1" ;;
    esac
}

cobalt_base() {
    local base="${SEKAI_COBALT_URL%/}"
    [ -n "$base" ] || return 1
    case "$base" in http://*|https://*) ;; *) base="https://$base" ;; esac
    printf '%s' "$base"
}

# The headers every request to the instance carries. The key goes in a file only this user can
# read, so no command line shows it.
make_hdr() {
    hdr="$tmpdir/hdr"
    ( umask 077; : >"$hdr"
      printf 'Accept: application/json\nContent-Type: application/json\n' >>"$hdr"
      [ -n "$SEKAI_COBALT_KEY" ] && printf 'Authorization: Api-Key %s\n' "$SEKAI_COBALT_KEY" >>"$hdr" )
}

# Fetches one address into one file and says the percent as it goes. An address on the cobalt
# instance is fetched with its key (a tunnel can want it).
fetch_file() {
    local from="$1" to="$2" part="$2.part" last=-1 line rc
    local extra=(-A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")
    local base
    if base="$(cobalt_base)" && [ "${from#"$base"}" != "$from" ] && [ -f "$tmpdir/hdr" ]; then
        extra+=(-H "@$tmpdir/hdr")
    fi
    : >"$part" || return 1
    curl -L --fail --silent --show-error --progress-bar --connect-timeout 20 "${extra[@]}" -o "$part" "$from" 2>&1 \
        | stdbuf -oL tr '\r' '\n' \
        | while IFS= read -r line; do
            if [[ $line =~ ([0-9]+)\.[0-9]% ]]; then
                if [ "${BASH_REMATCH[1]}" != "$last" ]; then
                    last="${BASH_REMATCH[1]}"
                    say "prog|${last}%||"
                fi
            fi
        done
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        rm -f "$part"
        return "$rc"
    fi
    mv -f "$part" "$to"
}

# A file name for item number $2 at address $1: the name in the address when it has one.
item_name() {
    local from="$1" i="$2" kind="$3" g ext name
    g="${from%%\?*}"
    name="${g##*/}"
    ext="${name##*.}"
    case "$ext" in
        jpg|jpeg|png|webp|gif|mp4|webm|mov|m4v|mp3|ogg|opus|wav|m4a) ;;
        *) ext=""; name="" ;;
    esac
    if [ -z "$ext" ]; then
        case "$kind" in video) ext="mp4" ;; gif) ext="gif" ;; *) ext="jpg" ;; esac
        name="item_${i}.${ext}"
    fi
    printf '%s' "$name"
}

run_cobalt() {
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        note_err "curl and jq are needed for cobalt."
        return 1
    fi
    local base
    if ! base="$(cobalt_base)"; then
        note_err "No cobalt instance is set. Put its address in Settings > Desktop > Downloader, or use yt-dlp."
        return 1
    fi
    say "engine|cobalt"

    local cmode="auto" q="$quality" cf="$afmt" style="${SEKAI_NAMES:-basic}"
    case "$mode" in audio) cmode="audio" ;; mute) cmode="mute" ;; esac
    case "$q" in max|2160|1440|1080|720|480|360) ;; *) q="1080" ;; esac
    case "$cf" in best|mp3|ogg|wav|opus) ;; *) cf="mp3" ;; esac
    case "$style" in classic|pretty|basic|nerdy) ;; *) style="basic" ;; esac

    local body resp
    body="$(jq -n --arg url "$url" --arg m "$cmode" --arg q "$q" --arg a "$cf" --arg s "$style" --arg sub "$SEKAI_SUBS" \
        '{url:$url, downloadMode:$m, videoQuality:$q, audioFormat:$a, filenameStyle:$s, localProcessing:"disabled"}
         + (if ($sub | test("^[a-z]{2}$")) then {subtitleLang:$sub} else {} end)')"
    make_hdr

    say "prog|||"
    if ! resp="$(curl -sS --max-time 40 -X POST -H "@$hdr" --data "$body" "$base/" 2>&1)"; then
        note_err "Can't reach $base: $(printf '%s' "$resp" | head -c 160)"
        return 1
    fi
    if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
        note_err "$base did not answer like a cobalt instance."
        return 1
    fi

    local status
    status="$(printf '%s' "$resp" | jq -r '.status // empty')"
    case "$status" in
        tunnel|redirect)
            local from name path
            from="$(printf '%s' "$resp" | jq -r '.url')"
            name="$(printf '%s' "$resp" | jq -r '.filename // "download"')"
            path="$(free_path "$name")"
            say "title|${path##*/}"
            if ! fetch_file "$from" "$path"; then
                note_err "The download stopped before the end."
                return 1
            fi
            say "file|$path"
            return 0
            ;;
        picker)
            local total
            total="$(printf '%s' "$resp" | jq -r '.picker | length')"
            if [ "$SEKAI_PICK" = "1" ] && [ "$total" -gt 1 ]; then
                # Not saved yet: the user chooses (the shell calls us again with "fetch").
                printf '%s' "$resp" | jq -r '.picker[] | "SEKAI|item|" + (.type // "photo") + "\t" + .url + "\t" + (.thumb // (if (.type // "photo") == "photo" then .url else "" end))'
                say "choose|$total"
                chose=1
                return 0
            fi
            # Several pictures / clips (a carousel): all of them, numbered.
            say "title|$total items"
            local i=0 kind from path
            while IFS=$'\t' read -r kind from; do
                i=$((i + 1))
                path="$(free_path "$(item_name "$from" "$i" "$kind")")"
                if ! fetch_file "$from" "$path"; then
                    note_err "Item $i of $total stopped before the end."
                    return 1
                fi
                say "prog|$((i * 100 / total))%||"
                last_file="$path"
            done < <(printf '%s' "$resp" | jq -r '.picker[] | [.type, .url] | @tsv')
            [ -n "$last_file" ] && say "file|$last_file"
            return 0
            ;;
        local-processing)
            note_err "This instance wants your machine to join the pieces, which this widget doesn't do. Try yt-dlp."
            return 1
            ;;
        error)
            note_err "$(cobalt_message "$(printf '%s' "$resp" | jq -r '.error.code // "unknown"')")"
            return 1
            ;;
        *)
            note_err "The instance answered something unexpected."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------------------
# fetch: the items the user chose in the picker.
# ---------------------------------------------------------------------------------------
run_fetch() {
    command -v curl >/dev/null 2>&1 || { note_err "curl is not installed."; return 1; }
    local items total i=0 kind from path
    items="$(printf '%s' "$SEKAI_ITEMS" | grep -v '^\s*$')"
    total="$(printf '%s\n' "$items" | grep -c .)"
    [ "$total" -gt 0 ] || { note_err "Nothing was chosen."; return 1; }
    cobalt_base >/dev/null && make_hdr
    say "title|$total item$([ "$total" = 1 ] || echo s)"
    say "prog|||"
    while IFS=$'\t' read -r kind from; do
        i=$((i + 1))
        case "$from" in
            ytdl:*|m3u8:*)
                # A video the picture tool can't fetch itself: yt-dlp does it.
                url="${from#ytdl:}"
                url="${url#m3u8:}"
                local keep_mode="$mode"; mode="video"
                run_ytdlp || return 1
                mode="$keep_mode"
                ;;
            *)
                path="$(free_path "$(item_name "$from" "$i" "$kind")")"
                if ! fetch_file "$from" "$path"; then
                    note_err "Item $i of $total stopped before the end."
                    return 1
                fi
                last_file="$path"
                ;;
        esac
        say "prog|$((i * 100 / total))%||"
    done <<<"$items"
    [ -n "$last_file" ] && say "file|$last_file"
    return 0
}

# ---------------------------------------------------------------------------------------
# Which message to show when everything that was tried failed: the first engine's, unless it
# only said "no video here" / "can't read that link" and a later one said something more useful.
# ---------------------------------------------------------------------------------------
pick_error() {
    local e
    for e in "${errs[@]}"; do
        if ! printf '%s' "$e" | grep -qiE 'no video|unsupported url|not installed|there is no video'; then
            printf '%s' "$e"
            return
        fi
    done
    printf '%s' "${errs[0]}"
}

# A hint for the failures a login would fix.
login_hint() {
    [ -n "$SEKAI_COOKIES$SEKAI_COOKIES_FILE" ] && return
    printf '%s' "$1" | grep -qiE 'log ?in|sign ?in|cookies|private|age-restricted|confirm your age|rate-limit|not available' \
        && printf ' (If you are logged in on a browser: Settings > Desktop > Downloader > Login from.)'
}

chain=()
case "$engine" in
    auto)
        command -v yt-dlp >/dev/null 2>&1 && chain+=(ytdlp)
        [ "$mode" = "video" ] && command -v gallery-dl >/dev/null 2>&1 && chain+=(gallerydl)
        [ -n "$SEKAI_COBALT_URL" ] && chain+=(cobalt)
        if [ "${#chain[@]}" -eq 0 ]; then
            fail "Nothing to download with. Install yt-dlp (pacman -S yt-dlp), or set a cobalt instance."
        fi
        ;;
    ytdlp|gallerydl|cobalt|fetch) chain=("$engine") ;;
    *) fail "Unknown engine: $engine" ;;
esac

ok=0
for e in "${chain[@]}"; do
    if "run_$e"; then
        ok=1
        break
    fi
done

if [ "$ok" -eq 1 ]; then
    # Asked the user which items: the shell asks, and calls again with "fetch".
    [ "$chose" -eq 1 ] && exit 0
    say "done"
    exit 0
fi

msg="$(pick_error)"
[ -n "$msg" ] || msg="It did not work."
fail "$msg$(login_hint "$msg")"
