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
config.leader = { key = "t", mods = "CTRL", timeout_milliseconds = 1000 }

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

wezterm.on("update-status", function(window, pane)
    local ws = window:active_workspace()
    record_ws(ws, pane_cwd(pane))
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
    -- LEADER T → the `t` fzf picker in a transient tab. fzf honors YOUR keybindings
    -- (FZF_DEFAULT_OPTS — e.g. Colemak Ctrl-k/Ctrl-h), and on select it emits the OSC
    -- that the user-var handler below turns into a SwitchToWorkspace. Run via a login
    -- shell so PATH + FZF_DEFAULT_OPTS are present; the tab closes when `t` exits.
    -- (WezTerm's built-in InputSelector has fixed, non-customizable keys — hence
    -- delegating to fzf, which is fully key-programmable.)
    {
        key = "T",
        mods = "LEADER",
        action = act.SpawnCommandInNewTab({
            args = { os.getenv("SHELL") or "/bin/zsh", "-lc", "t" },
        }),
    },
    -- LEADER S → built-in launcher: switch between EXISTING workspaces only.
    {
        key = "S",
        mods = "LEADER",
        action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }),
    },
    -- Previous / next workspace  (tmux: prefix ( / ) )
    { key = "(", mods = "LEADER", action = act.SwitchWorkspaceRelative(-1) },
    { key = ")", mods = "LEADER", action = act.SwitchWorkspaceRelative(1) },
    -- Create a new named workspace and switch to it
    {
        key = "N",
        mods = "LEADER",
        action = act.PromptInputLine({
            description = "New workspace name:",
            action = wezterm.action_callback(function(window, pane, line)
                if line and line ~= "" then
                    window:perform_action(
                        act.SwitchToWorkspace({ name = line }),
                        pane
                    )
                end
            end),
        }),
    },
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

-- ----------------------------------------------------------------------------
-- Shell-driven workspace switching (complements LEADER T).
-- The `t` shell script emits an OSC 1337 SetUserVar named "switch-workspace" whose
-- value is "<workspace-name>\t<cwd>". WezTerm's CLI can't change the active
-- workspace, so the switch has to happen here, GUI-side.
-- ----------------------------------------------------------------------------
wezterm.on("user-var-changed", function(window, pane, name, value)
    if name ~= "switch-workspace" then
        return
    end
    local ws, dir = value:match("^(.-)\t(.*)$")
    if not ws or ws == "" then
        return
    end
    -- Only pass `spawn` when the workspace does NOT already exist. Switching to an
    -- existing workspace with a spawn arg triggers a repaint stall (the pane doesn't
    -- redraw until an input event); a plain SwitchToWorkspace(name) — what the
    -- built-in launcher does — switches cleanly.
    local exists = false
    for _, w in ipairs(wezterm.mux.get_workspace_names()) do
        if w == ws then
            exists = true
            break
        end
    end
    local spawn = (not exists and dir and dir ~= "") and { cwd = dir } or nil
    window:perform_action(
        act.SwitchToWorkspace({ name = ws, spawn = spawn }),
        pane
    )
    record_ws(ws, dir)
end)

return config
