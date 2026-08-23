-- Hyprland behavior for the dotless base: startup, keybinds, and the service
-- submap. Spliced verbatim into hyprland.lua by the module's extraConfig.
--
-- Declarative config (input/general/decoration, env, window rules) stays in
-- Nix (settings.*); this is the imperative half. Commands are bare names on
-- PATH; anything needing a Nix store path is a named wrapper the module installs
-- (hypr-play-sound, hypr-polkit-agent, hypr-set-wallpaper), so this file needs
-- no interpolation and stays static.
--
-- luacheck: globals hl
-- luacheck: no max line length

-- Accordion zoom/nav in native hl calls. hyprctl's classic "dispatch <name>"
-- string is parsed as Lua under the new config format, so shelling out to it
-- (the old wrapper scripts) no longer dispatches - it errors.

-- Float the focused window at 95% of the monitor, centered, so tiles peek
-- behind. Monitor size is physical; divide by scale for the logical geometry
-- hl.window.resize expects.
local function zoom_window()
  local m = hl.get_active_monitor()
  hl.dispatch(hl.dsp.window.float())
  hl.dispatch(hl.dsp.window.resize({
    x = math.floor(m.width / m.scale * 0.95),
    y = math.floor(m.height / m.scale * 0.95),
  }))
  hl.dispatch(hl.dsp.window.center())
end

-- SUPER+comma toggles the zoom: float+size on the way in, back into the tile
-- (float again) on the way out.
local function accordion_zoom()
  local w = hl.get_active_window()
  if w and w.floating then
    hl.dispatch(hl.dsp.window.float())
  else
    zoom_window()
  end
end

-- Focus nav. While zoomed (floating) swap the big window for the next tiled
-- one: drop the current back into the tile, cycle, hand the newcomer the zoom.
-- When tiled, plain geometric focus move.
--   previous: cycle backwards; direction: focus move when tiled
local function accordion_nav(previous, direction)
  local w = hl.get_active_window()
  if w and w.floating then
    hl.dispatch(hl.dsp.window.float())
    hl.dispatch(hl.dsp.window.cycle_next({ tiled = true, previous = previous }))
    zoom_window()
  else
    hl.dispatch(hl.dsp.focus({ direction = direction }))
  end
end

-- ── Startup (fires once per session, not on reload) ─────────────────────────
hl.on("hyprland.start", function()
  -- Propagate compositor env to the systemd user session (portals, services).
  hl.exec_cmd([[dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland]])
  hl.exec_cmd([[hypr-polkit-agent]]) -- polkit privilege-escalation dialogs
  hl.exec_cmd([[awww-daemon]]) -- wallpaper daemon
  hl.exec_cmd([[hypr-set-wallpaper]]) -- awww wait && awww img <profile wallpaper>
  -- Clipboard history - watch both text and image events.
  hl.exec_cmd([[wl-paste --type text --watch cliphist store]])
  hl.exec_cmd([[wl-paste --type image --watch cliphist store]])
end)

-- ── Essentials ──────────────────────────────────────────────────────────────
hl.bind("SUPER + Return", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })) -- zoom, press again to restore
hl.bind("SUPER + SHIFT + Return", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })) -- true fullscreen
hl.bind("SUPER + CTRL + t", hl.dsp.exec_cmd([[alacritty]]))
hl.bind("SUPER + CTRL + e", hl.dsp.exec_cmd([[emacsclient -c -a emacs]]))
hl.bind("SUPER + CTRL + f", hl.dsp.exec_cmd([[firefox]]))
hl.bind("SUPER + CTRL + w", hl.dsp.exec_cmd([[librewolf]]))
hl.bind("SUPER + CTRL + period", hl.dsp.exec_cmd([[nautilus]]))
hl.bind("SUPER + CTRL + v", hl.dsp.exec_cmd([[cliphist list | wofi --dmenu | cliphist decode | wl-copy]]))
hl.bind("SUPER + SHIFT + backspace", hl.dsp.window.close())
hl.bind("SUPER + space", hl.dsp.exec_cmd([[wofi --show drun]]))

-- ── Focus (HJKL): accordion stack while zoomed, else geometric movefocus.
--    k/l cycle forward, h/j back. ──────────────────────────────────────────
hl.bind("SUPER + h", function() accordion_nav(true, "up") end)
hl.bind("SUPER + j", function() accordion_nav(true, "left") end)
hl.bind("SUPER + k", function() accordion_nav(false, "down") end)
hl.bind("SUPER + l", function() accordion_nav(false, "right") end)

-- ── Move window (h = up, j = left, k = down, l = right) ─────────────────────
hl.bind("SUPER + SHIFT + h", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + j", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + k", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + SHIFT + l", hl.dsp.window.move({ direction = "right" }))

-- ── Layout ──────────────────────────────────────────────────────────────────
hl.bind("SUPER + slash", hl.dsp.layout("togglesplit")) -- tiles horizontal / vertical
hl.bind("SUPER + comma", accordion_zoom) -- 95% float, tiles peek behind

-- ── Resize (relative deltas, matching resizeactive) ─────────────────────────
hl.bind("SUPER + minus", hl.dsp.window.resize({ x = -50, y = -50, relative = true }))
hl.bind("SUPER + equal", hl.dsp.window.resize({ x = 50, y = 50, relative = true }))

-- ── Workspaces: numbers 1-9, and letters a-z minus the hjkl nav keys.
--    Workspace name matches the Colemak keysym - press the key you see. ──────
for i = 1, 9 do
  hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
  hl.bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i), follow = true }))
end
for letter in ("abcdefgimnopqrstuvwxyz"):gmatch("%a") do
  local ws = "name:" .. letter:upper()
  hl.bind("SUPER + " .. letter, hl.dsp.focus({ workspace = ws }))
  hl.bind("SUPER + SHIFT + " .. letter, hl.dsp.window.move({ workspace = ws, follow = true }))
end

-- ── Workspace navigation ────────────────────────────────────────────────────
hl.bind("SUPER + tab", hl.dsp.focus({ workspace = "previous" })) -- back-and-forth
hl.bind("SUPER + SHIFT + tab", hl.dsp.workspace.move({ monitor = "+1" }))

-- ── Media keys ──────────────────────────────────────────────────────────────
-- Brightness varies per machine (backlight device); add it in local.lua.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd([[swayosd-client --output-volume raise; hypr-play-sound]]))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd([[swayosd-client --output-volume lower; hypr-play-sound]]))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd([[swayosd-client --output-volume mute-toggle; hypr-play-sound]]))

-- ── Screenshots (grimblast: copy + save to ~/Pictures/Screenshots) ──────────
hl.bind("Print", hl.dsp.exec_cmd([[grimblast --notify copysave screen]]))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd([[grimblast --notify copysave area]]))
hl.bind("SUPER + Print", hl.dsp.exec_cmd([[grimblast --notify copysave active]]))

-- ── Files workspace ─────────────────────────────────────────────────────────
hl.bind("SUPER + period", hl.dsp.focus({ workspace = "name:." }))
hl.bind("SUPER + SHIFT + period", hl.dsp.window.move({ workspace = "name:.", follow = true }))

-- ── Service submap (mnemonic Colemak keys; SUPER+SHIFT+o enters, resets after
--    any action) ────────────────────────────────────────────────────────────
hl.bind("SUPER + SHIFT + o", hl.dsp.submap("service"))
hl.define_submap("service", "reset", function()
  hl.bind("escape", hl.dsp.submap("reset"))
  hl.bind("f", function()
    hl.dispatch(hl.dsp.window.float())
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("r", function()
    hl.dispatch(hl.dsp.exec_cmd([[hyprctl reload]]))
    hl.dispatch(hl.dsp.exec_cmd([[notify-send -u low -t 2000 "Hyprland" "Config reloaded"]]))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("l", hl.dsp.exec_cmd([[hyprlock]]))
end)
