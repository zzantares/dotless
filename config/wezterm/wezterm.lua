local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- Font
config.font_size = 12
config.line_height = 1.2
config.font = wezterm.font("CaskaydiaCove Nerd Font")

-- Theme (Kanagawa Dragon — warm, muted, darker variant)
config.color_scheme = "Kanagawa Dragon (Gogh)"
config.colors = {
    cursor_bg = "#c8c093",
    cursor_border = "#c8c093",
    tab_bar = {
        background = "rgba(24, 22, 22, 0.9)",
        active_tab = {
            bg_color = "#8ba4b0",
            fg_color = "#181616",
            intensity = "Bold",
        },
        inactive_tab = {
            bg_color = "rgba(24, 22, 22, 0.7)",
            fg_color = "#625e5a",
        },
        inactive_tab_hover = {
            bg_color = "#282727",
            fg_color = "#c5c9c5",
        },
        new_tab = {
            bg_color = "rgba(24, 22, 22, 0.7)",
            fg_color = "#625e5a",
        },
        new_tab_hover = {
            bg_color = "#282727",
            fg_color = "#c5c9c5",
        },
    },
}

-- Multiplexer domain.
-- Workspaces live in wezterm-mux-server, not in the GUI, so closing the window
-- leaves every workspace and the processes in it running and the next GUI
-- reattaches. Without this a closed window kills them, which is the one thing a
-- detached tmux session gives you.
--
-- The server auto-spawns on first connect. Its pid lock is per-user
-- ($XDG_RUNTIME_DIR/wezterm/pid), not per-socket, so only one can run at a time;
-- after a wezterm version bump, kill the old one if a client refuses to connect.
config.unix_domains = { { name = "main" } }
config.default_domain = "main"

-- Window
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.92
config.window_padding = {
    left = 16,
    right = 16,
    top = 12,
    bottom = 12,
}

-- Tab bar
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
-- Keep the tab bar visible even with a single tab, so the workspace indicator in
-- the right status is always shown.
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 32

-- Panes
config.inactive_pane_hsb = {
    saturation = 0.8,
    brightness = 0.7,
}

-- Misc
config.enable_scroll_bar = false
-- Generous scrollback for keyboard copy-mode (LEADER [) navigation. Default is 3500;
-- this keeps a long tail of normal command output reachable without the trackpad.
-- Note: this does NOT capture alt-screen apps (vim, less, htop, or Claude Code in its
-- default fullscreen renderer) — that content never enters the scrollback buffer. To
-- make Claude Code's output land here, run it with the classic renderer:
--   CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1  (or `/tui default` in-session).
config.scrollback_lines = 100000

-- Rendering backend. macOS + the default WebGpu backend has repaint stalls where a
-- programmatically-created window (e.g. the one SwitchToWorkspace spawns from the
-- `user-var-changed` handler) doesn't repaint on PTY output until an input/focus
-- event. OpenGL avoids that, and also renders window_background_opacity correctly on
-- macOS (WebGpu disables it). Flip back to "WebGpu" if you prefer and don't hit this.
config.front_end = "OpenGL"

-- ============================================================================
-- tmux-style key bindings
--   Leader / prefix: CTRL+t  (press & release, then the command key)
--   "windows" in tmux == tabs in wezterm; "panes" map 1:1.
--   This is WezTerm's own multiplexer layer. It nests cleanly with tmux: WezTerm
--   owns CTRL+t while tmux keeps its CTRL+b prefix (see programs/tmux), so a tmux
--   session running inside WezTerm receives CTRL+b untouched.
-- ============================================================================
-- tmux-style: effectively never expire the prefix while waiting for the command
-- key. WezTerm has no true "no timeout", so use a large value; the 1s default
-- made fast two-key combos feel rushed.
config.leader =
    { key = "t", mods = "CTRL", timeout_milliseconds = 1000 * 60 * 60 }

-- ---------------------------------------------------------------------------
-- Workspace MRU (most-recently-active first).
-- Tracks workspace activation so LEADER g can toggle to the last active workspace
-- and the `t` picker can order candidates by recency. Populated by an update-status
-- poll (catches every switch) plus the explicit switch points below; persisted to a
-- cache file for the `t` shell script. Each entry: { name, cwd }.
-- ---------------------------------------------------------------------------
local ws_mru = {}
local ws_mru_path = (os.getenv("HOME") or "") .. "/.cache/wezterm-workspace-mru"

local function persist_ws_mru()
    local lines = {}
    for _, e in ipairs(ws_mru) do
        table.insert(lines, e.name .. "\t" .. (e.cwd or ""))
    end
    pcall(function()
        local f = io.open(ws_mru_path, "w")
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
        end
    end)
end

local function pane_cwd(pane)
    local ok, uri = pcall(function()
        return pane and pane:get_current_working_dir()
    end)
    if not ok or not uri then
        return nil
    end
    local path
    if type(uri) == "userdata" then
        path = uri.file_path -- newer wezterm: Url object
    elseif type(uri) == "string" then
        path = uri:gsub("^file://[^/]*", "") -- older wezterm: file:// URL
    end
    if not path or path == "" then
        return nil
    end
    -- WezTerm reports directory cwds with a trailing slash; strip it so the cache
    -- matches zoxide's slash-free form (avoids duplicate picker entries).
    local stripped = path:gsub("/+$", "")
    if stripped ~= "" then
        path = stripped
    end
    return path
end

local function record_ws(name, cwd)
    if not name or name == "" then
        return
    end
    if ws_mru[1] and ws_mru[1].name == name then
        if cwd and cwd ~= "" then
            ws_mru[1].cwd = cwd
        end
        return
    end
    for i, e in ipairs(ws_mru) do
        if e.name == name then
            table.remove(ws_mru, i)
            break
        end
    end
    table.insert(ws_mru, 1, { name = name, cwd = cwd })
    persist_ws_mru()
end

-- Active-mode indicators for the left status. WezTerm gives no cue that a key
-- table is active (copy via LEADER [, resize via LEADER r), so surface it as a
-- colored pill. Keys are the names window:active_key_table() reports.
local mode_indicators = {
    copy_mode = { label = "COPY", bg = "#dca561" }, -- kanagawa yellow
    resize_pane = { label = "RESIZE", bg = "#8ea4a2" }, -- kanagawa muted teal
    search_mode = { label = "SEARCH", bg = "#c4746e" }, -- kanagawa red
}

wezterm.on("update-status", function(window, pane)
    local ws = window:active_workspace()
    record_ws(ws, pane_cwd(pane))
    -- Drop the "\u{25cf} " marker `claude-attention` puts on a tab once you are
    -- looking at it (mirrors tmux's client-session-changed hook).
    local ok, tab = pcall(function()
        return window:active_tab()
    end)
    if ok and tab then
        local title = tab:get_title()
        if title and title:match("^\u{25cf} ") then
            tab:set_title(title:gsub("^\u{25cf} ", ""))
        end
    end
    -- Left status: light up a pill while a key table (copy/resize/search) is
    -- active, so an otherwise invisible mode is obvious. Cleared when none is.
    local mode = mode_indicators[window:active_key_table()]
    if mode then
        window:set_left_status(wezterm.format({
            { Background = { Color = mode.bg } },
            { Foreground = { Color = "#181616" } },
            { Attribute = { Intensity = "Bold" } },
            { Text = " " .. mode.label .. " " },
        }))
    else
        window:set_left_status("")
    end
    -- Show the active workspace name in the status bar (like tmux's session name),
    -- as a small colored pill matching the active-tab colors.
    window:set_right_status(wezterm.format({
        { Background = { Color = "#8ba4b0" } },
        { Foreground = { Color = "#181616" } },
        { Attribute = { Intensity = "Bold" } },
        { Text = " " .. ws .. " " },
    }))
end)

-- Tab titles: a tab you explicitly renamed (LEADER ,) keeps its name; otherwise show
-- the foreground executable's name (zsh, nvim, git, …), falling back to the pane
-- title if the process name isn't available.
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
    local title = tab.tab_title
    if not title or title == "" then
        local ok, p = pcall(wezterm.mux.get_pane, tab.active_pane.pane_id)
        local proc
        if ok and p then
            local ok2, name = pcall(function()
                return p:get_foreground_process_name()
            end)
            if ok2 and name and name ~= "" then
                proc = name:match("([^/]+)$") -- basename of the executable path
            end
        end
        title = proc or tab.active_pane.title or "shell"
    end
    title = wezterm.truncate_right(title, math.max(max_width - 5, 6))
    return string.format(" %d: %s ", tab.tab_index + 1, title)
end)

-- ---------------------------------------------------------------------------
-- Workspace pickers: LEADER T/B/S over the live workspaces, LEADER N over the
-- zoxide directories. Both are InputSelector overlays, so both pick up the
-- Colemak list_nav key table (h = up, k = down).
-- A directory's workspace name is always <parent>/<base>, which is how
-- `git wt start` names sessions, so picking a worktree lands on the workspace
-- it already made instead of a second one.
-- ---------------------------------------------------------------------------
local function ws_name_for_dir(dir)
    local parts = {}
    for part in string.gmatch(dir, "[^/]+") do
        table.insert(parts, part)
    end
    if #parts == 0 then
        return dir
    elseif #parts == 1 then
        return parts[1]
    end
    return parts[#parts - 1] .. "/" .. parts[#parts]
end

local function tilde(path)
    local home = os.getenv("HOME") or ""
    if home ~= "" and path:sub(1, #home) == home then
        return "~" .. path:sub(#home + 1)
    end
    return path
end

-- Two columns: name padded to the widest, capped so one long name cannot push
-- every path off screen. The path stays in the label, so fuzzy matching sees
-- it as well as the name.
local function padded_choices(rows)
    local width = 0
    for _, r in ipairs(rows) do
        width = math.max(width, math.min(#r.name, 34))
    end
    local choices = {}
    for _, r in ipairs(rows) do
        local label = string.format("%-" .. width .. "s  %s", r.name, r.shown or "")
        table.insert(choices, { id = r.id, label = (label:gsub("%s+$", "")) })
    end
    return choices
end

-- Frecency order is zoxide's own, so never sort.
local function zoxide_choices()
    local ok, stdout = wezterm.run_child_process({ "zoxide", "query", "-l" })
    if not ok then
        return {}
    end
    local rows = {}
    for dir in string.gmatch(stdout, "[^\r\n]+") do
        table.insert(rows, {
            id = dir,
            name = ws_name_for_dir(dir),
            shown = tilde(dir),
        })
    end
    return padded_choices(rows)
end

-- Live workspaces, most recently active first, leaving out the one you are in:
-- switching there is a no-op, and dropping it puts the last-used workspace on
-- row 1. cwds come from the MRU cache, so one never visited shows none.
local function live_ws_choices(current)
    local live, rows, seen = {}, {}, {}
    for _, name in ipairs(wezterm.mux.get_workspace_names()) do
        live[name] = true
    end
    local function add(name, cwd)
        if live[name] and name ~= current and not seen[name] then
            seen[name] = true
            table.insert(rows, {
                id = name,
                name = name,
                shown = cwd and tilde(cwd) or "",
            })
        end
    end
    for _, e in ipairs(ws_mru) do
        add(e.name, e.cwd)
    end
    -- Anything live but never recorded (e.g. created by `git wt start` while
    -- this window was elsewhere) goes after the MRU block, name-sorted.
    local rest = {}
    for name in pairs(live) do
        if name ~= current and not seen[name] then
            table.insert(rest, name)
        end
    end
    table.sort(rest)
    for _, name in ipairs(rest) do
        add(name, nil)
    end
    return padded_choices(rows)
end

local function ws_is_live(name)
    for _, w in ipairs(wezterm.mux.get_workspace_names()) do
        if w == name then
            return true
        end
    end
    return false
end

-- spawn only when the workspace does not exist yet: passing it for a live one
-- stalls the repaint, same reason the user-var handler below never passes it.
local function open_dir_as_workspace(window, pane, dir)
    local name = ws_name_for_dir(dir)
    local args = { name = name }
    if not ws_is_live(name) then
        args.spawn = { cwd = dir }
    end
    window:perform_action(act.SwitchToWorkspace(args), pane)
end

-- Shared picker flow: push the nav table, show the list, pop it again from the
-- selector's callback, which fires on accept and on cancel alike.
local function show_picker(window, pane, opts)
    if #opts.choices == 0 then
        window:toast_notification("wezterm", opts.empty, nil, 4000)
        return
    end
    window:perform_action(
        act.ActivateKeyTable({ name = "list_nav", one_shot = false }),
        pane
    )
    window:perform_action(
        act.InputSelector({
            title = opts.title,
            fuzzy = true,
            fuzzy_description = "workspace> ",
            choices = opts.choices,
            action = wezterm.action_callback(function(win, p, id)
                win:perform_action(act.PopKeyTable, p)
                if id then
                    opts.on_pick(win, p, id)
                end
            end),
        }),
        pane
    )
end

-- LEADER B / T / S: switch to a live workspace.
local switch_ws_picker = wezterm.action_callback(function(window, pane)
    show_picker(window, pane, {
        title = "Switch workspace",
        choices = live_ws_choices(window:active_workspace()),
        empty = "no other workspace is open",
        on_pick = function(win, p, name)
            win:perform_action(act.SwitchToWorkspace({ name = name }), p)
        end,
    })
end)

-- LEADER N: open a zoxide directory as a workspace.
local open_ws_picker = wezterm.action_callback(function(window, pane)
    show_picker(window, pane, {
        title = "Open workspace",
        choices = zoxide_choices(),
        empty = "zoxide returned no directories",
        on_pick = open_dir_as_workspace,
    })
end)

config.keys = {
    -- Send a literal CTRL+t to the program (tmux convention: prefix then prefix).
    -- Requires CTRL held on the 2nd key so it doesn't shadow `LEADER t` (the
    -- workspace switcher below).
    {
        key = "t",
        mods = "LEADER|CTRL",
        action = act.SendKey({ key = "t", mods = "CTRL" }),
    },

    -- Splits  (tmux: % = left/right divider, " = top/bottom divider)
    {
        key = "%",
        mods = "LEADER",
        action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
    },
    {
        key = "\"",
        mods = "LEADER",
        action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
    },
    -- convenience aliases, Vim-style (v = :vsplit → left/right, s = :split → top/bottom)
    {
        key = "v",
        mods = "LEADER",
        action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
    },
    {
        key = "s",
        mods = "LEADER",
        action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
    },

    -- Pane focus  (Colemak hjkl: h=up, j=left, k=down, l=right; arrows too)
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    {
        key = "LeftArrow",
        mods = "LEADER",
        action = act.ActivatePaneDirection("Left"),
    },
    {
        key = "DownArrow",
        mods = "LEADER",
        action = act.ActivatePaneDirection("Down"),
    },
    {
        key = "UpArrow",
        mods = "LEADER",
        action = act.ActivatePaneDirection("Up"),
    },
    {
        key = "RightArrow",
        mods = "LEADER",
        action = act.ActivatePaneDirection("Right"),
    },

    -- Cycle to next pane  (tmux: prefix + o)
    { key = "o", mods = "LEADER", action = act.ActivatePaneDirection("Next") },
    -- Rotate/swap panes  (tmux: prefix + { / })
    {
        key = "{",
        mods = "LEADER",
        action = act.RotatePanes("CounterClockwise"),
    },
    { key = "}", mods = "LEADER", action = act.RotatePanes("Clockwise") },

    -- Zoom current pane  (tmux: prefix + z)
    { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

    -- Kill pane  (tmux: prefix + x). confirm=false keeps the original preference;
    -- tmux actually prompts y/n — flip to confirm=true to mirror that.
    {
        key = "x",
        mods = "LEADER",
        action = act.CloseCurrentPane({ confirm = false }),
    },
    -- Kill window/tab  (tmux: prefix + &)
    {
        key = "&",
        mods = "LEADER",
        action = act.CloseCurrentTab({ confirm = true }),
    },

    -- Tabs == tmux windows
    { key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
    -- Rename tab  (tmux: prefix + ,)
    {
        key = ",",
        mods = "LEADER",
        action = act.PromptInputLine({
            description = "Rename tab:",
            action = wezterm.action_callback(function(window, _, line)
                if line then
                    window:active_tab():set_title(line)
                end
            end),
        }),
    },

    -- Copy mode  (tmux: prefix + [)   and   paste  (tmux: prefix + ])
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
    { key = "]", mods = "LEADER", action = act.PasteFrom("Clipboard") },

    -- LEADER t → jump to the most recently active tab (tmux: last-window).
    { key = "t", mods = "LEADER", action = act.ActivateLastTab },
    -- LEADER g → jump to the most recently active WORKSPACE (tmux last-window, but for
    -- workspaces). ws_mru[1] is the current one, so ws_mru[2] is the previous. Recording
    -- immediately after the switch makes repeated presses toggle between the two.
    {
        key = "g",
        mods = "LEADER",
        action = wezterm.action_callback(function(window, pane)
            local prev = ws_mru[2]
            if prev then
                window:perform_action(
                    act.SwitchToWorkspace({ name = prev.name }),
                    pane
                )
                record_ws(prev.name, prev.cwd)
            end
        end),
    },

    -- Sessions == WezTerm workspaces (the analog of a tmux session).
    -- LEADER B / T / S → the workspace picker, all three the same thing; B and T
    -- mirror the tmux `t` binds. Runs GUI-side with no shell, no spawn and no
    -- escape sequence to stall on. Type to filter, Enter to switch.
    { key = "B", mods = "LEADER", action = switch_ws_picker },
    { key = "T", mods = "LEADER", action = switch_ws_picker },
    { key = "S", mods = "LEADER", action = switch_ws_picker },
    -- Previous / next workspace  (tmux: prefix ( / ) )
    { key = "(", mods = "LEADER", action = act.SwitchWorkspaceRelative(-1) },
    { key = ")", mods = "LEADER", action = act.SwitchWorkspaceRelative(1) },
    -- Open a zoxide directory as a workspace  (tmux: the `t` picker)
    { key = "N", mods = "LEADER", action = open_ws_picker },
    -- Rename current workspace  (tmux: prefix $)
    {
        key = "$",
        mods = "LEADER",
        action = act.PromptInputLine({
            description = "Rename workspace:",
            action = wezterm.action_callback(function(_, _, line)
                if line and line ~= "" then
                    wezterm.mux.rename_workspace(
                        wezterm.mux.get_active_workspace(),
                        line
                    )
                end
            end),
        }),
    },

    -- Repeatable resize mode  (tmux-ish): prefix + r, then hjkl/arrows, Esc to exit
    {
        key = "r",
        mods = "LEADER",
        action = act.ActivateKeyTable({
            name = "resize_pane",
            one_shot = false,
            timeout_milliseconds = 1000,
        }),
    },
}

-- Select tab by number  (tmux: prefix + <n>). 1-indexed here: prefix+1 == first
-- tab (matches tmux with `base-index 1`). Use ActivateTab(i) for tmux's 0-based default.
for i = 1, 9 do
    table.insert(config.keys, {
        key = tostring(i),
        mods = "LEADER",
        action = act.ActivateTab(i - 1),
    })
end

-- ============================================================================
-- Key tables
-- ============================================================================
config.key_tables = {
    -- Colemak-DH list navigation for the LEADER N picker: h = up, k = down, as
    -- in resize mode below. The selector overlay hardcodes its own keys (CTRL+k
    -- is up there), and a binding is looked up before the key reaches the
    -- overlay, so remapping to the arrows it also accepts wins.
    list_nav = {
        { key = "h", mods = "CTRL", action = act.SendKey({ key = "UpArrow" }) },
        { key = "k", mods = "CTRL", action = act.SendKey({ key = "DownArrow" }) },
    },

    -- Repeatable resize mode entered via prefix + r.
    resize_pane = {
        { key = "h", action = act.AdjustPaneSize({ "Up", 2 }) },
        { key = "j", action = act.AdjustPaneSize({ "Left", 2 }) },
        { key = "k", action = act.AdjustPaneSize({ "Down", 2 }) },
        { key = "l", action = act.AdjustPaneSize({ "Right", 2 }) },
        { key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 2 }) },
        { key = "DownArrow", action = act.AdjustPaneSize({ "Down", 2 }) },
        { key = "UpArrow", action = act.AdjustPaneSize({ "Up", 2 }) },
        { key = "RightArrow", action = act.AdjustPaneSize({ "Right", 2 }) },
        -- exit resize mode
        { key = "Escape", action = "PopKeyTable" },
        { key = "Enter", action = "PopKeyTable" },
        { key = "q", action = "PopKeyTable" },
    },
}

-- ----------------------------------------------------------------------------
-- Copy mode: start from WezTerm's (already vi/tmux-flavored) defaults and apply
-- a few tmux copy-mode-vi tweaks. We overwrite-in-place so it doesn't matter
-- whether wezterm matches the first or last entry for a given key.
-- ----------------------------------------------------------------------------
local function set_key(tbl, key, mods, action)
    for _, e in ipairs(tbl) do
        if e.key == key and (e.mods or "NONE") == mods then
            e.action = action
            return
        end
    end
    table.insert(tbl, { key = key, mods = mods, action = action })
end

local copy_mode = wezterm.gui.default_key_tables().copy_mode

local copy_and_close = act.Multiple({
    act.CopyTo("ClipboardAndPrimarySelection"),
    act.ClearSelection,
    act.ScrollToBottom,
    act.CopyMode("Close"),
})

-- tmux: Enter copies the selection and exits copy mode (default `y` already does this)
set_key(copy_mode, "Enter", "NONE", copy_and_close)
-- tmux: / and ? start an incremental search from within copy mode
set_key(copy_mode, "/", "NONE", act.Search("CurrentSelectionOrEmptyString"))
set_key(copy_mode, "?", "NONE", act.Search("CurrentSelectionOrEmptyString"))

-- Colemak navigation: h=up, j=left, k=down, l=right (overrides wezterm's vi defaults)
set_key(copy_mode, "h", "NONE", act.CopyMode("MoveUp"))
set_key(copy_mode, "j", "NONE", act.CopyMode("MoveLeft"))
set_key(copy_mode, "k", "NONE", act.CopyMode("MoveDown"))
set_key(copy_mode, "l", "NONE", act.CopyMode("MoveRight"))

config.key_tables.copy_mode = copy_mode
-- search_mode defaults already give you n/N-style cycling via Enter / Ctrl-n / Ctrl-p.

return config
