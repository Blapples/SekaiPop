-- ######## Window rules ########

-- Disable blur for xwayland context menus
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })

-- Floating dialogs
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
-- The shell's avatar / banner picker (kdialog, zenity or yad: scripts/images/pick-image.sh)
hl.window_rule({match = {title = "^(Choose your (avatar|banner))$" },        center = true})
hl.window_rule({match = {title = "^(Choose your (avatar|banner))$" },        float = true})
hl.window_rule({match = {title = "^(Choose your (avatar|banner))$" },        size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Select the mod file to import)(.*)$" },  center = true}) -- Gale
hl.window_rule({match = {title = "^(Select the mod file to import)(.*)$" },  float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})
hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true})
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true})
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {class = ".*plasmawindowed.*" },                     float = true})
hl.window_rule({match = {class = "kcm_.*" },                                 float = true})
hl.window_rule({match = {class = ".*bluedevilwizard" },                      float = true})
hl.window_rule({match = {title = ".*Welcome" },                              float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })

-- Move
-- KDE's colour-scheme / icon-theme change (what Settings > Desktop > System colours and
-- Appearance > Icons trigger) can spawn this window. Keep it out of the way.
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, float = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, no_initial_focus = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, move = {999999, 999999}})
-- stupid dolphin copy
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- Tiling
-- Ignore app maximize requests so restored window states do not override tiling.
hl.window_rule({match = {class = ".*" }, suppress_event = "maximize"})
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true})

-- Picture-in-Picture
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- Screen sharing
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- Pinned windows get their own border colour
hl.window_rule({match = {pin = 1 }, border_color = "rgba(c2c9b4AA) rgba(c2c9b477)"})

-- --- Tearing ---
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- Shadows: every window gets one (tiled ones too) while Settings -> Hyprland -> Shadows is on.
-- This used to switch them off for tiled windows, which is why they looked missing.

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## Layer rules ########
-- Every surface of the shell has a namespace starting with "sekaipop-" (the bar is plain
-- "quickshell": Quickshell's default, since Bar.qml sets none). They draw their own motion
-- (the phone slides and bounces, the cards pop, the keyboard rises), and Hyprland's layer
-- animation on top of that shows up as a flash or a lifted edge (see CHANGELOG: quickpanel,
-- keyboard, region picker). So the compositor's animation is off for all of them.
--
-- To give some of them Hyprland's animation back, narrow the regex below (e.g. list only the
-- ones you want switched off) instead of "^sekaipop-".
hl.layer_rule({ name = "sekaipop-no-anim", match = { namespace = "^sekaipop-" }, no_anim = true })

-- No blur anywhere on the shell: its surfaces are opaque. To blur one, e.g. the notification cards:
--   hl.layer_rule({ match = { namespace = "^sekaipop-notifications$" }, blur = true, ignore_alpha = 0.3 })

-- Launchers need to be FAST (GTK4 layer-shell apps: fuzzel-style launchers, wlogout, ...)
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})

-- The phone mirror (sekaipop/services/PhoneMirrorService.qml). The embedded scrcpy window is
-- never seen: the shell parks it off every monitor, then pins it under the phone's screen.
-- Keep it floating, unfocused at first, and without animation, blur or shadow.
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, float = true})
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, move = {99000, 99000}})
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, no_initial_focus = true})
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, no_anim = true})
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, no_blur = true})
hl.window_rule({match = {title = "^(sekai-phone-embed)$" }, no_shadow = true})
-- The small window that shows the phone's lock screen so a PIN can be typed.
hl.window_rule({match = {title = "^(sekai-phone-unlock)$" }, float = true})
hl.window_rule({match = {title = "^(sekai-phone-unlock)$" }, center = true})
