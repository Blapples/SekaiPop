# The phone wallpaper

The phone's home screen (the Quick Panel) and its Apps screen show a wallpaper behind
them, seen as an LCD: the picture at nearly full strength under a fine pixel mesh, cut to
the phone's glass. When the notification list is empty, the notifications card says so
in one quiet line instead of staying blank. Issue [#41](https://github.com/Blapples/SekaiPop/issues/41).

## Using it

- **Settings > General > Quick Panel > Phone wallpaper**: **Off**, **Desktop** (the
  wallpaper of the monitor the phone is open on; a video wallpaper's first frame), or
  **A picture** of your own. The same choice applies to both screens.
- **A picture**, the first time, opens a file chooser. Only a picked picture turns it on:
  cancelling leaves things as they were. While it is on, **Change the phone's picture**
  picks another. The window that opens is **Picture picker** (the same one the avatar
  and banner use).
- The picture is copied into `~/.local/share/sekaipop/` (as `phone-<time>.<ext>`, scaled
  down if it is far bigger than the phone can show), like the avatar and banner, so moving
  or deleting the original doesn't matter.
- Over the wallpaper, the home screen's two cards (the buttons and the notifications)
  let some of it through, and the name under the avatar is white with a dark edge, like
  the app names on the Apps screen. The clock, date and speed sit on the banner and keep
  its own ink rule.

## Settings

- `phone.wallpaper`: `"off"`, `"desktop"` or `"picture"`. Empty until it has been chosen
  once; then the Apps screen's old switch, `launcher.lcdWallpaper` (on by default), says
  it: on is Desktop, off is Off. So someone who had turned the Apps screen's wallpaper off
  keeps a plain phone.
- Desktop presets carry the mode like any other setting, and the phone's picture itself
  (issue [#147](https://github.com/Blapples/SekaiPop/issues/147)), as they carry the
  avatar and banner: a copy, `phone.<ext>`, in the preset's `<name>.images/` folder, and
  its framing. Wearing the preset puts that copy back as the phone's picture, even when
  you have picked another since. A preset saved with no phone picture, or before presets
  carried it, leaves yours alone (it is only ever shown in "A picture" mode, which the
  preset's own setting decides), and its "you are wearing this one" tick ignores it.

## How it works

- `modules/common/PanelImages.qml`: `phone` / `phonePath` (the picked picture),
  `phoneMode` (the rule above) and `phoneWallpaperFor(monitor)`, the file path both
  screens show ("" for none).
- `scripts/images/pick-image.sh` and `shrink-image.sh` know a third kind, `phone`
  (scaled to cover 1600 x 3000 at most).
- `LauncherLcd.qml` draws it, on both screens, at z -10: `LauncherFace.qml` (Apps) and
  `QuickPanelFace.qml` (Quick). The Quick face stays pure UI: `QuickPanel.qml` hands it
  the path (`wallpaperPath`) for the monitor it is on.
- Over it, `QuickPanelFace` sets its cards' fills to `cardAlpha` (0.78) of their colour
  and hides the notification card's shadow, which would show through a see-through card
  as a dark slab. Translucency, not blur: the picture is static and cheap this way.
- The empty notifications card picks one of a few lines (`emptyNote` in
  `QuickPanelFace.qml`) each time the list empties.

- Presets: `DesktopPresetService.qml` puts `images.phone` in a capture only when there
  is a picture, hands the worn path to `preset-state.sh save` as its sixth argument
  (`wornPictures()`), and `wearImages()` restores it with the avatar and banner. The
  tick has one more variant (`noPhonePicture` in `variantKey()` / `digestsOf()`) so a
  preset without the entry still matches.

Tests: `tests/phone-test/phone_wallpaper_test.js` (the rules, the wiring, the script),
`tests/launcher-test/lcd_source_test.js`, and `tests/preset-images-test/preset_images_unit.js`
(the preset part, its tick, and `preset-state.sh` saving and restoring it for real).
