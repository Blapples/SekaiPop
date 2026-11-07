# Manga and novel readers

A manga reader (left side of the screen) and a novel reader (right side), as panels over the desktop.
Ported from [dhrruvsharma/shell](https://github.com/dhrruvsharma/shell) (GPL-3.0-or-later): their QML
and their Python backends, with the colours taken from SekaiPop's theme (so the panels follow the
palette, light / dark / darker and matugen) instead of their own.

- **Manga:** browse each source's own **Popular** (the default) and **Latest** lists, or search and filter
  with AniList (genre, tags, origin, format, status, score, year, 18+; sorted by trending, popular, top
  rated or favourites), a library
  (your AniList lists as tabs, and the titles you saved), favourites with a check for new chapters,
  downloads, and a chapter reader. The chapters and pages come from WeebCentral or MangaDex (the
  **Source** key beside Filters in Browse switches them).
- **Novels:** browse, search, a library, and a reader in the panel. Sources: FreeWebNovel, Chikari and
  NovelArrow, switched from the panel.

## Using it

```sh
qs -c sekaipop ipc call mangareader toggle     # also: show, hide, minimize, close
qs -c sekaipop ipc call novelreader toggle     # also: show, hide, minimize, close
```

`SUPER + CTRL + M` and `SUPER + CTRL + N` are the binds in `hypr/hyprland/keybinds.lua`. Update now
doesn't touch the Hyprland config, so on an existing install add those two lines yourself (or run
install.sh again).

The manga panel opens as a **full window** (the whole screen, with the 12 px margin the card always
has). A size key in its header, between minimize and close, switches it to the 650 px card on the
left edge and back; the choice is kept in `reader.json` (`fullWindow`, on by default). In the full
window the Browse and Saved grids put more covers in a row (about one per 190 px, 4 to 10), and the
reader's own full-screen key gives the screen back instead of widening the card. The novel panel is
unchanged.

A panel has two keys in its header (the manga panel a third, the size key), and there is no tab left on the screen edge:

- **Minimize** shrinks the panel into the edge and leaves it running in the background: the reader
  and its server stay up and the panel is exactly as you left it. The only way back is the shortcut
  (`toggle` / `show`), which grows it out of the edge again.
- **Close** shrinks it into the edge and unloads it, which stops the reader and its server
  completely. The next open starts it fresh. (`hide` and the shortcut while the panel is open do the
  same as Close.)

While a chapter is read the header is hidden, so use the shortcut there. The panels open on the
focused monitor.

Nothing is built or run until you open one.

## The look

The panels are built from the shell's own parts, so they read as part of it and not as a second app
at the screen edge:

- the panel is the flat card of the bar's popups (navy outline, inner ring in Dark / Darker, hard
  shadow underneath) floating a little off the screen edge, with a `SekaiPlate` header: the reader's
  name as a sticker, the Browse / Library `SegmentSwitch` and two diamond keys, minimize and close;
- it **pops in** out of its screen edge from nothing, with a little overshoot, and is **swallowed** all the
  way back into it when closed: a pure scale, no fade (340 ms in, 240 ms out, eased at both ends so it
  really reaches nothing); minimize and close both end in the bare edge, and a minimized panel grows
  back out of it;
- covers are cards of the same build (outline, hard shadow, the press that sinks the card into its
  shadow), with outlined, slightly tilted stamps for type and status;
- chips, back / sort / font keys and the Prev / Next keys are Pills (`ReaderChip`, `ReaderKey`);
  search is the wallpaper board's `SearchPill`;
- the detail page's cover is a taped, tilted photo on a halftone;
- while a chapter is read, a capsule bar floats over it (tap the page to slide it away), the page
  counter is a sticker, and progress is an outlined pill (`ReaderProgress`).

The chapter text of the novel reader stays in a book face (Noto Serif); everything else uses the
shell's font.

## Source: WeebCentral, MangaDex or Suwayomi

The key left of **Filters** in Browse shows the source (WeebCentral, MangaDex or, once it is set up,
Suwayomi); tapping it goes to the next one. The choice is kept in `~/.local/share/sekaipop/readers/manga/provider.json`.

- **WeebCentral** reads the site's HTML (see below).
- **MangaDex** uses MangaDex's own JSON API, so it needs no scraping: a few small requests per title.
  Chapters are English by default (`SEKAIPOP_MD_LANG=<code>` in the shell's environment changes the
  language). When two groups uploaded the same chapter, the fuller one is shown. Official links that
  have no pages on MangaDex are left out. MangaDex lists the AniList id of many series, so those
  match at once with no guessing. Pages come from MangaDex@Home servers; the panel never holds their
  short-lived links (it asks this server, which asks MangaDex for a fresh server when one fails), so a
  long chapter keeps loading. `SEKAIPOP_MD_QUALITY=data-saver` gives the smaller pictures. MangaDex
  asks for about 5 requests a second and the server keeps under that. It asks readers to credit
  MangaDex and the scanlation group: the title page says where the chapters come from.
- **Suwayomi** is a local server that runs Mihon / Tachiyomi extensions, so one source gives you
  every site those extensions cover. It is offered in the Source key only when you set it up:
  - **`install.sh` / `install-deps.sh` set this up for you** (skip it with `--no-suwayomi`): they add
    the full Java runtime (`jre-openjdk`, 21+) when there is none (a headless-only Java is swapped for it), download the latest Suwayomi-Server jar to
    `~/.local/share/suwayomi/Suwayomi-Server.jar` and write `~/.local/share/suwayomi/run.sh` (java with
    no browser window and no tray icon). This server finds `run.sh` by itself, so the Source key offers
    Suwayomi with no environment variable. Run `install-deps.sh` again after deleting the jar to update
    it; `check-deps.sh` reports Java, the jar and the launcher. Suwayomi ships with no extensions: add a
    repository and install extensions from the panel's **Sources** page (below).
  - By hand instead, `SEKAIPOP_SW_CMD="java -jar ~/.local/share/suwayomi/Suwayomi-Server.jar"` makes this server start
    Suwayomi when it is first needed (the first open takes a few seconds) and stop it when the reader
    closes; its output goes to `suwayomi.log` beside `provider.json`. A Suwayomi you started yourself
    is used as it is and never stopped. Without a command, set `SEKAIPOP_SW_URL=http://127.0.0.1:4567`
    to say it is already running.
  - **Extensions are managed in the panel, not in Suwayomi's web page.** While Suwayomi is offered, a
    puzzle key sits beside the Source key in Browse and opens the **Sources** page, with three tabs:
    - **Repositories**: the extension indexes Suwayomi reads (links to an `index.min.json`). Add one by
      pasting its link, or with one tap for the suggested **Keiyoushi** repository
      (`https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`); remove one with the
      bin key. A new repository is read at once. Extensions are made by other people and run on this
      computer, so add only repositories you trust.
    - **Extensions**: everything the repositories list, searchable. **Install**, **Update** and **Remove**
      on each row, **Update all**, and **Refresh** to ask the repositories again. The list shows your
      language (`SEKAIPOP_SW_LANG`, default `en`) and multi-language extensions; the language key cycles
      through the others and **18+** shows adult ones. What is installed is always listed.
    - **Sources**: every source the installed extensions brought. By default it is automatic (your
      language and multi-language sources, the first 8 by name, no 18+). Tick or untick a source to choose
      them yourself: the pick is kept in `~/.local/share/sekaipop/readers/manga/sw_sources.json`, may hold
      sources of any language, and a source from an extension you install later joins it. **Back to
      automatic** drops the pick. A pick wins over `SEKAIPOP_SW_SOURCES`, `SEKAIPOP_SW_LANG` and
      `SEKAIPOP_SW_NSFW`, which still apply while nothing is picked.
    Searches and Latest ask several sources at once and mix the answers; the label on each card (and in the
    match picker) is the source it came from.
    **One source at a time:** every picked Suwayomi source is a choice of the Source chip, like WeebCentral
    and MangaDex: the chip shows the current source's name and a tap goes on to the next
    (`WeebCentral → MangaDex → <picked sources> → WeebCentral`). Two sources with one name get their
    language added (`X · en`, `X · ja`). There is no all-sources choice; with nothing picked, Suwayomi has no
    choice in the cycle. On a Suwayomi source, Latest shows only that source's list and titles are matched
    against only it. The choice is not kept across a restart (the first picked source is used again), and a
    series that was already matched stays on the source it was matched to.
    The first time the page opens, Suwayomi may be starting (a
    few seconds); an install downloads the extension, so it can take a little longer, and the row shows a
    spinner meanwhile. The page talks to Suwayomi through the server's `/sw/*` routes (local only), and
    reads which fields this Suwayomi has by GraphQL introspection, so a Suwayomi update should not break it;
    if one does, `suwayomi.log` and the server's output say what Suwayomi answered. Suwayomi's own web page
    (`http://127.0.0.1:4567`) still works, but nothing needs it.
  - Suwayomi's own login is not supported: leave it off (it only listens on this computer).
    Suwayomi has no AniList link, so a title is matched by its names, like WeebCentral.
- The sources do not share anything: a MangaDex series has an id that starts with `md-` and a Suwayomi one with `sw-`, so its
  library entry, favourite, downloads and read marks are its own, and the match you pick for a title
  is kept per source (`anilist_matches.json`). A title opened from the library opens with the source
  it was saved from, whichever one is picked now.
- **Popular** and **Latest** in Browse are the picked source's own lists, the way Mihon opens a source (it opens on
  Popular), and ask nothing of AniList. Each Suwayomi source is asked for its own Popular and Latest feed. There is
  no sort row on them: the two tabs are the sorts. The server's `GET /browse?sort=popular|latest&page=n` answers
  it (it can also sort by `rating` or `views` where the source has them, and says so in `sorts`, but nothing in the
  panel asks for those). Changing the source goes back to Popular.
- The **Library** shows the source too: the same Source key sits beside Filters on your AniList lists (titles opened from them are read from that source), and every cover in **Saved** has a small MANGADEX, SUWAYOMI or WEEBCENTRAL tag, because a saved title keeps the site it was saved from.

## Browse: AniList for finding, WeebCentral or MangaDex for reading

Like Seanime, the manga panel finds titles through AniList (the search, the filters, the covers,
scores, descriptions and genres) and reads them from WeebCentral. The first time a title is opened,
the server looks its name up on WeebCentral (English and romaji titles, then a few synonyms) and
keeps the best match if the name is close enough (`MATCH_MIN`, 0.88). A title that only has a
sequel or side story on WeebCentral is not matched on its own, since a shared name is not proof.

When there is no match, or the wrong one, the strip under the cover shows **Pick match** /
**Change**: it lists the closest WeebCentral series, and typing searches WeebCentral for that text.
A pick is kept in `~/.local/share/sekaipop/readers/manga/anilist_matches.json` until you change it
(**Use automatic match** lets go of it). The library, favourites, downloads and the reader still
work on the WeebCentral series, so they behave as before; a library entry that came from AniList
opens with the AniList details too.

The **Filters** key opens a row of keys, one per filter (Genre, Tags, Origin, Format, Status, Min score,
Max score, Year, 18+). A key drops its list down under the row, with a tick on what is on; each change
searches again, and a key is lit while it has something on. Genre, Tags and Status can have several on
at once (the list stays open while you tick; none on means any); the others pick one and close. **Tags**
are AniList's own list (a few hundred, so they are looked up when you first open the list and kept in
`~/.local/share/sekaipop/readers/manga/al_tags.json` for a week): the list has a search box, each tag shows
its category in grey, and the tags that are on also sit in a row under the keys to tap off. 18+ tags show
only with 18+ on. **Min score** and **Max score** keep titles by AniList's average score, shown out of 10
like on the cards (7.0+ keeps 70 and over, Up to 8.0 keeps 80 and under); a title AniList has no score for
is left out while either is set. **Clear** switches every filter off.

Typing in the search box searches AniList, and so does touching a filter (the **AniList** tab is where its
Trending / Popular / Top rated / Favourites sorts are); the **Popular** and **Latest** tabs are the source's own
lists and have no filters. AniList answers about 30 requests a minute; the
server waits once and retries if it is told to slow down.

## Long synopses

The synopsis beside the cover shows three lines. If the title has more, a **More** key appears under it (a tap
on the text works too) and the whole synopsis drops down under the cover, pushing the chapters down; it
scrolls inside if it is taller than about 40% of the window. **Less** folds it back. It folds by itself when
you open another title.

## Continue reading

A **Continue** key sits at the bottom right of a title's chapter list and opens the chapter where you left
off, **on the page you stopped on** (the key says which: "Continue · CH.12 · p.8"). The reader keeps the page
you are on in every chapter you have begun and not finished, in `manga/pages.json` beside `read.json`, and
drops it once the chapter is read. Only Continue goes back to that page; tapping a chapter in the list starts
it from the first page. Which one that is: the chapter you opened last, if you did not finish it (a chapter counts as read once
its last page has been on screen); otherwise the first unread chapter after the furthest one you have read.
A title you have not begun shows **Start** with chapter one. It goes by the reading order, not by how the
list is sorted or filtered, steps aside while you select chapters or have the Info panel open, and is hidden
once every chapter is read.

## The Info panel

The **Info** key under a title's cover slides a sheet down into the chapter area and pushes the chapter list
down ahead of it (the cover and the strip above stay in view; the key is lit while it is open, and pressing
it again or the X in the panel pulls it back up). Pressing the key again mid-slide turns it round smoothly,
and the list keeps its scroll position and selection. It shows everything AniList knows about the title:

- **Status**: Ongoing, Completed, On hiatus, Cancelled or Not yet released (AniList's Releasing /
  Finished, in plain words), with the chapter and volume count once it is finished.
- **Released**: the start date, and the end date for a finished or cancelled series (or "now").
- **Translation**: the original language, then **Official English** with the sites (AniList's English
  read-online links: Webtoon, Tapas, Comikey, ...), or **Licensed** when AniList marks it licensed but lists
  no English site, or **Not licensed, fan translation**. That last line comes only from AniList's licence flag:
  AniList does not know scanlation groups, and a licence it has not recorded reads as a fan translation.
  **Reading** says where the chapters in the panel come from (WeebCentral, in English).
- **Ratings**: everyone's average out of 10, with how many people have it on their list and how many
  favourited it, and **yours** in your own score format (out of 10, 100, 5 stars or smileys, as your AniList
  is set). Rate it on AniList; the panel only shows it.
- **Tracking**: *Tracked* with the status and chapters read (and an Edit key that opens the track sheet),
  *Not tracked* when it is not on your list yet, or what is missing (the login, or an AniList id).
- **Other names**: English, romaji, native and AniList's synonyms.
- **Genres and tags**: every one, tags with their percentage, best first. Spoiler tags stay hidden until
  you press *Show N spoilers*.

The cover also carries stamps: the status, AniList's score, **YOU** and your score, the year, and
**TRACKED** while it is on your list. Your score and the tracked state need the AniList login; a series
that was not opened from AniList (and has no AniList match) has no Info beyond its title.

## AniList account

The key at the right of the header plate (a person in a circle, left of Browse / Library; it is lit
while you are logged in) opens the AniList page. Logging in uses AniList's
[implicit grant](https://docs.anilist.co/guide/auth/implicit): the token comes back in the *fragment*
of the redirect URL, which a server never sees, so the redirect URL is a page of the reader's own
server whose script hands the token to it. No client secret is used, so none ships with the shell.

**Once:** make an app at <https://anilist.co/settings/developer> (Create New Client), set its
**Redirect URL** to exactly `http://127.0.0.1:5150/al/auth/callback`, and paste its **Client ID** (a
number) into the page. (`SEKAIPOP_ANILIST_CLIENT_ID` in the environment of the shell works instead.)

**Each login:** *Log in with AniList* opens the browser; approve the app; the tab says "Logged in as
...", and the panel notices by itself. If the redirect page can't be reached, set the app's Redirect URL
to `https://anilist.co/api/v2/oauth/pin` instead, log in, and paste the token it shows into the field
that the page offers while it waits.

What is kept and where: `~/.local/share/sekaipop/readers/manga/anilist_auth.json` (mode 600) holds the
client ID, the token (AniList's last a year; the date is read from it) and your name, avatar and score
format. The token is never sent to the panel or to any web page: `/al/auth/status` says only who is
logged in. A login only finishes for a request that carries the nonce of a login started from the panel
(so a web page can't log the shell in to someone else's account), the endpoints refuse other origins and
hosts, and the token is checked with AniList before it is kept. AniList turning a token down (revoked,
expired) logs out by itself. **Log out** forgets the token here; to cancel it on AniList too, remove the
app under Apps in your AniList settings.

## Reading progress and AniList tracking

**Read / unread (every title).** A chapter is read once its last page has been on screen (or you go on
to the next chapter from it). Read chapters are dimmed in the list with a check at the right, and the
list header says how many are read. Opening one again says "Already read", the bar shows a READ stamp,
and the key beside the settings key (check = read) marks it unread again. Long-press or right-click a
chapter to select, then tap more; the bar at the bottom has **All**, **Up to here** (that chapter and
every one before it), **Read** and **Unread**; the ... key by the sort key has Select chapters, Mark
all as read and Mark all as unread. Kept in `~/.local/share/sekaipop/readers/manga/read.json`, by
chapter id.

**Tracking on AniList (needs the login above, and a title opened from Browse).** The AniList key under
the cover (Track, then e.g. "AniList - Reading 12") opens the track sheet: pick the status (Reading,
Planning, Completed, Paused, Dropped, Rereading) and the number of chapters read, and Save. With
**Update as I read** on (the AniList page; on by default), a moment after chapters are marked read the
highest chapter number read is sent to AniList: a title that is not on your list, or is Planning /
Paused / Dropped, becomes Reading, and reaching the last chapter AniList knows makes it Completed. The
automatic update only ever raises the number: marking a chapter unread, or reading an old one, never
lowers it (the sheet's Save can). A series that WeebCentral lists by volume updates AniList's volume
count. `Update as I read` is kept in `tracking.json` next to the library. The server side is
`/al/track` (the list entry), `/al/track/progress` and `/al/track/set`; they answer the panel only,
like the login.

## Library: your AniList lists

With an AniList login the **Library** tab opens on your own lists, as tabs: **Reading**, **Completed**,
**Dropped** and **Planning** (there is no All: a title is always in one list), with **Paused** and
**Rereading** added while they hold something, and **Saved** last, the covers you put there with
**+ Library** (that is all the tab holds without a login, where a key offers the login). A count follows
each tab's name.

A list is a table like AniList's own manga list: cover and title, **Score** (in the format your AniList
is set to: 10 point, 10 point decimal, 100 point, 5 stars or 3 smileys), **Chapters** read out of the
total ("164/250", just "21" when AniList has no total), **Volumes** (left out while the panel is
narrow) and **Type**. Tapping a title opens the same page as in Browse (chapters, the track sheet).

The **title filter** at the top narrows the open tab by name (English, romaji or native). **Filters**
opens the keys, the same kind of dropdowns as in Browse: **Sort** (Score, Title, Progress, Last updated,
Last added), **Genre**, **Tags**, **Origin**, **Format** (Manga, One shot, Novel), **Status** (the
title's own: Releasing, Finished, ...) and **Year** (the year it started). Genre, Tags and Status can have
several on; a title has to have every genre and tag that is on, as on AniList. **Clear** switches the
filters off. They stay while you change tab.

The server reads your whole list from AniList once (`/al/list`, in chunks of 500) and keeps it for a
minute; the tab, the filters and the sort are cut out of that copy, so changing them asks AniList for
nothing. A change you make in the track sheet or by reading (**Update as I read**) drops the copy, and the
Library asks again whenever it is shown. Your custom lists are not shown. Like the login and the tracking,
the route answers the panel only.

## The profile page

The account key in the header opens the AniList page; with a login it shows your profile, top to bottom:

- **The card:** banner, avatar, name, "N followers · N following", chapters read, mean score, titles tracked.
  Your AniList banner is the top of the card; when you have none, the banner is drawn in your AniList profile
  colour (and that colour is the ring round the avatar), else in the shell's accent.
- **Stats strip:** volumes read, titles completed, titles scored, and chapters read per title tracked (the
  card already has chapters read, mean score and titles tracked).
- **Status bar:** how the list splits between Reading, Completed, Dropped and Planning (Paused and
  Rereading while they hold something), with the counts. Display only.
- **Can't decide?:** **Pick something for me** draws one random title from Planning and shows its cover and
  facts. **Not this one** draws another (never the one on screen), **Open** goes to it. Nothing is asked
  until you tap.
- **Jump back in:** the Library titles you read last; a tap opens the page you stopped at.
- **Recent activity:** your latest AniList list updates, newest first, as covers with what the update said and
  how long ago ("Ch. 52 · 2h", "Completed · 1d"); a tap opens the title.
- **Reading now:** your AniList Reading list, last updated first, with the progress on each.
- **Almost done:** Reading titles with 5 chapters or fewer to go (needs AniList to know the total and you to
  have started), the fewest left first.
- **Stalled:** Reading titles whose AniList entry has not changed for 30 days or more, the longest idle first,
  with the chapter you stopped at and the days idle. An entry AniList gives no time for is not counted.
- **Up next:** your Planning list, best rated on AniList first (unrated last), with the community score on the
  cover. A tap opens the title. The three shelves show at most 16 titles each and are hidden while empty.
- **Top rated:** the titles you scored highest, with the score stamp in your own score format.
- **Because you rated X highly:** up to three shelves, one for each of your top scored titles (70 or more out of
  100) that AniList's readers have recommendations for: what they recommend, best rated first, leaving out
  everything already on your list and novels. A title is on one shelf only, under the title whose readers
  rated it highest, and a title with fewer than three recommendations gets no shelf.
- **Favourites**, then **Scores** (how your scores spread, one column per point of your own scale: 1 to 10,
  stars or smileys; a decimal score goes to the nearest point, a 100-point score to the nearest ten), then
  **Breakdown** (four small bar charts: type of what you read (manga, manhwa, manhua, one-shot, novel), the
  decade it started in (older than 1990 is one bar), the tags you read most with count and mean score, and the
  creators you read most; the first two are counted from your list without Planning, the last two are AniList's
  statistics, and AniList does not say who wrote and who drew, so the creators are one list; a name opens
  their AniList page), then **Taste** (your most read genres as bars with count and mean score, and a heatmap
  of the days you updated your list in the last 26 weeks; AniList folds repeated updates to one title
  into one, so it counts list updates, not chapters; under it your current streak, longest streak, updates this
  week and this month, and the busiest day. A streak still counts if today has no update yet), then **About** (your bio as plain text) and **Account**.

The stats strip, the status bar, Reading now, Almost done, Stalled, Up next, Scores, Top rated and the pick are cut out of the list the Library already holds
(`/al/overview`, `/al/pick`), so they ask AniList for nothing new. The heatmap is `/al/activity` (up to six
pages of your list activity, kept ten minutes; it is left out if it fails). The bio, the follower and
following totals and the genre statistics come with `/al/profile`. All of them answer the panel only.

Four things are asked of AniList on top of that, each on its own so that one it refuses leaves out only itself
(it is logged as `profile extra left out` and the rest of the page is unchanged): `/al/extras` (profile colour,
tag and creator statistics, kept ten minutes, and the activity feed, kept two) and `/al/recs` (one question for
the recommendations of your top scored titles, kept ten minutes). None of these questions has been tried
against the real AniList yet.

## The backends

Each panel starts a small local server (`sekaipop/scripts/readers/`) that fetches from the source
sites, and only listens on `127.0.0.1` (manga **5150**, novels **5151**). They need Python and
`curl_cffi` or `requests`:

```sh
sekaipop/scripts/readers/setup-venv.sh
```

makes a private venv (`~/.local/share/sekaipop/readers/venv`) with both; the servers use it when it is
there and the system `python3` when it is not. If a panel stays empty, `qs -c sekaipop log` shows the
server's output (a missing module, or the port taken).

Your data: `~/.local/share/sekaipop/readers/` (libraries, favourites, downloads);
`~/.cache/sekaipop/readers/` (novel chapter cache).

The scrapers read other people's sites, so they break when a site changes its markup. A source that
stops working is fixed in `scripts/readers/manga_server.py` (manga) or
`scripts/readers/novel_server/providers/` (one file per novel source).

## Files

```
modules/sekai/readers/
  ReaderHost.qml      the window, the two panels, minimize / close, the ipc handlers
  ReaderPanel.qml     the frame both panels share: card, header plate, tabs, pop-in / swallow
  MangaReader.qml     the manga panel (Browse / Library -> Detail -> Reader)
  NovelReader.qml     the novel panel
  ReaderChip.qml ReaderKey.qml ReaderBadge.qml ReaderBar.qml ReaderProgress.qml CoverCard.qml
  ReaderField.qml     a one-line text field (client ID, pasted token)
                      the parts built on the shell's Pill: keys, stamps, the floating bar, progress
  manga/ novel/       their views (Browse, Detail, Library, Reader; manga also has FilterMenu,
                      the list a filter key drops down, MatchPicker, the WeebCentral series picker, and
                      AniListLogin, the AniList account page, TrackSheet, a title's status and progress on it, and
                      InfoPanel, the Info panel)
  Manga.qml Novel.qml the services: state, library file, backend process
  Colors.qml          the readers' Material 3 colour roles, worked out from Theme
  ReaderEnv.qml       where the backends are and which python runs them
  (the rest)          small shared pieces: CoverCard, Spinner, Skeleton*, IconButton, ...
scripts/readers/      manga_server.py, novel_server/, setup-venv.sh
```
