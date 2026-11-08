# Kinetic lyrics (Whole screen)

The lyrics widget has a second look: kinetic typography over the whole desktop.

Turn it on: Settings -> Desktop -> Lyrics -> **Whole screen**, or

    qs -c sekaipop ipc call lyrics kinetic on      # off to go back to the card
    qs -c sekaipop ipc call lyrics kineticToggle   # bind this to a key
    qs -c sekaipop ipc call lyrics dim 0.5         # vignette behind the words, 0 .. 0.85
    qs -c sekaipop ipc call lyrics colors theme    # theme (default) | sekai | accent
    qs -c sekaipop ipc call lyrics camera still    # still | drift (default)
    qs -c sekaipop ipc call lyrics style wall      # poster (default) | wall | marquee
    qs -c sekaipop ipc call lyrics styleCycle      # the next style: bind this to a key

The words, their timing, the sources (Boidu first) and `lyrics nudge` are the card's. The
window takes no clicks and sits under your windows. It is not shown in Edit Desktop.

## Styles

Settings -> Desktop -> Lyrics -> **Whole screen style** (or `ipc lyrics style ...`). All three
use the same words, timing, colours, dim and camera setting; only the layout and motion differ.
Only the style that is on is built.

- **Poster** (default): the look above: every line is its own composition, the words slam in.
- **Wall**: the whole song is one huge wall of type, each line a block against the left, the right
  or the middle, stacked down the wall, and the whole wall is turned a couple of degrees. The camera
  flies from **word to word**: it pushes in on the word that is being sung (about half of the
  screen's width, never more than about twice what its line needs) and sets off a moment before it,
  so it has arrived as the word starts; the moves add up, so words in a row blend into one glide.
  The wall swings a little more while the camera is moving. In the line that is on only the word
  that is sung is bright: the words already sung are coloured and a little dimmer, the ones to come
  faint. The lines round it are smaller, blurrier and dimmer the further they are. A very long
  word is set smaller so it never leaves the wall. **Still** stops the swing and the slow zoom on top
  (the flight is the look). Files: `KineticWall.qml`, `KineticWallLine.qml`.
- **Marquee**: five rows (three on a short screen). The one in the middle is the **hero**: it is the
  biggest, it does not scroll on its own but glides so that the word that is being sung is in the
  middle of the screen, and its words are outline only until sung, then solid in ONE colour for the
  whole line. The rows above and below are smaller the further they are, hollow and faint, and slide
  across in turns at their own speeds; a sung word only tints them. A darker band lies behind the
  hero row so the words read on any wallpaper. A new line's rows slide in from the side they move
  away from, one after the other, and the old line's rows leave the way they move. The texture rows
  run on the lyrics clock, so they stop with the music. Files: `KineticMarquee.qml`,
  `KineticMarqueeLine.qml`, `KineticMarqueeRow.qml`.

The maths of Wall and Marquee is in `modules/common/functions/KineticStyles.js` (no QML, tested
with node); `KineticFillWord.qml` is their flat word (no sticker).

## Korean and Japanese words

A word with any Hangul, kana or kanji in it is set in **Pretendard Black**, in the card and in all
three Whole screen styles; every other word keeps the theme's font. Install it with
`yay -S ttf-pretendard` (or `install-deps.sh`, which downloads `Pretendard-Black.otf` into
`~/.local/share/fonts/sekaipop-pretendard`); check with `fc-list "Pretendard:style=Black"`. Plain
Pretendard has Hangul and kana; most kanji come from Noto CJK. For every kanji in Pretendard too,
install `PretendardJP-Black.otf` and set `FAMILY = "Pretendard JP"` in
`modules/common/functions/LyricsFont.js` (the one place the name is set). Without the font the
words use the theme's font. A kanji-only word counts too (a Chinese line gets Pretendard's shapes).

## Colors

`theme` (default) takes the active theme's two accents, its glint colour and a deeper shade of
each, so a group palette, matugen and a monitor's own theme all re-colour it live. The vignette
and the sticker outline are the theme's navy. `sekai` is the five attribute pastels; `accent`
uses only the two accents.

## Presets

The look rides in a desktop preset with the rest of the lyrics (on / off, Whole screen, its style,
colors and dim). A preset saved before it existed wears the lyrics card as it always was (kinetic
off, dim 0.45, colors theme, style poster), whatever the look is now (`before` in `services/PresetWidgets.qml`). The
sync nudges stay yours.

## What it does

- Each line is a composition over the full screen: giant, stack, slash, burst, flow, arc
  (`modules/common/functions/KineticMath.js`). Same line, same picture; never the same style twice in a row.
- Words are ghosts until sung, then slam in, squash, ring, diamonds; colour fills as sung.
- Lines leave before the next starts. The camera drifts very slowly in / out line by line (or stays
  **still**); the screen never pulses with the words, only the words move.
- Instrumental gaps are three big diamonds.

## Tuning

Poster: everything is in `KineticMath.js`: `STYLE_LISTS` (which styles a line of N words may use),
`ENTER_S` / `LEAVE_S` (timings), `motionFor` (how each style throws its words), `camera`.
`node tests/lyrics-test/kinetic_unit.js` checks every layout stays on screen and apart.

Wall: `WALL_SIZE` (type size of a line, of the screen's height), `WALL_WLEAD` / `WALL_WMOVE` (when the camera
sets off before a word and how long a glide takes), `wallWordZoom` (how hard it pushes in on a word),
`WALL_TILT` / `WALL_ROLL_MAX` (the tilt and its swing), `wallDepth` (how small and blurry the far
lines are), `wallShade` (how dim they are), `wordGlow` (how long a word stays bright). Marquee:
`marqueeRows` (the row sizes and how faint the texture rows are), `voiceFollow` (how the hero row
glides), `MARQ_GAP_EM` / `MARQ_SEP_EM`, `marqueeAt` (how rows come and go). The
same test file checks the wall stays on the wall, the camera never jumps, and a strip always covers
the screen.

Untested in a live Quickshell (no Qt where it was written).
