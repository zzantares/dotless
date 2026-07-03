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
config.hide_tab_bar_if_only_one_tab = true

-- Panes
config.inactive_pane_hsb = {
	saturation = 0.8,
	brightness = 0.7,
}

-- Misc
config.enable_scroll_bar = false

-- ============================================================================
-- tmux-style key bindings
--   Leader / prefix: CTRL+t  (press & release, then the command key)
--   "windows" in tmux == tabs in wezterm; "panes" map 1:1.
--   This is WezTerm's own multiplexer layer. It nests cleanly with tmux: WezTerm
--   owns CTRL+t while tmux keeps its CTRL+b prefix (see programs/tmux), so a tmux
--   session running inside WezTerm receives CTRL+b untouched.
-- ============================================================================
config.leader = { key = "t", mods = "CTRL", timeout_milliseconds = 1000 }

-- Workspace switcher: zoxide + fzf picker that creates or switches to a
-- workspace named after the chosen directory (git root when possible).
local function workspace_switcher(window, pane)
	local home = os.getenv("HOME") or ""

	local script = [[
    printf '=== workspaces ===\n'
    wezterm cli list --format json 2>/dev/null \
      | grep -o '"workspace": *"[^"]*"' \
      | sed 's/"workspace": *"//;s/"$//' \
      | sort -u
    printf '=== directories ===\n'
    zoxide query -l 2>/dev/null
  ]]

	-- WezTerm launched from the GUI (Spotlight/Dock) inherits only a minimal PATH,
	-- so bare `wezterm`/`zoxide` aren't found. Prepend the Nix profile bins.
	local child_path = "/etc/profiles/per-user/"
		.. (os.getenv("USER") or "")
		.. "/bin:/run/current-system/sw/bin:"
		.. home
		.. "/.nix-profile/bin:"
		.. (os.getenv("PATH") or "")

	local success, stdout, stderr =
		wezterm.run_child_process({ "/usr/bin/env", "PATH=" .. child_path, "bash", "-c", script })
	if not success then
		wezterm.log_error("workspace switcher: " .. (stderr or "unknown error"))
		return
	end

	local choices = {}
	local seen = {}
	local section = ""

	for line in stdout:gmatch("[^\r\n]+") do
		if line == "=== workspaces ===" then
			section = "workspace"
		elseif line == "=== directories ===" then
			section = "directory"
		elseif line ~= "" then
			local label
			if section == "workspace" then
				label = "[active]  " .. line
			else
				local display = line
				if home ~= "" and line:sub(1, #home) == home then
					display = "~" .. line:sub(#home + 1)
				end
				label = display
			end

			if not seen[line] then
				seen[line] = true
				table.insert(choices, { id = line, label = label })
			end
		end
	end

	window:perform_action(
		act.InputSelector({
			title = "Switch workspace",
			choices = choices,
			fuzzy = true,
			action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
				if not id then
					return
				end

				local git_root = nil
				local git_ok, git_out, _ =
					wezterm.run_child_process({ "/usr/bin/env", "PATH=" .. child_path, "git", "-C", id, "rev-parse", "--show-toplevel" })
				if git_ok and git_out then
					git_root = git_out:match("^%s*(.-)%s*$")
				end

				local base_dir = git_root or id
				local ws_name = base_dir:match("([^/]+)$") or id

				inner_window:perform_action(
					act.SwitchToWorkspace({
						name = ws_name,
						spawn = { cwd = id },
					}),
					inner_pane
				)
			end),
		}),
		pane
	)
end

config.keys = {
	-- Send a literal CTRL+t to the program (tmux convention: prefix then prefix).
	-- Requires CTRL held on the 2nd key so it doesn't shadow `LEADER t` (the
	-- workspace switcher below).
	{ key = "t", mods = "LEADER|CTRL", action = act.SendKey({ key = "t", mods = "CTRL" }) },

	-- Splits  (tmux: % = left/right divider, " = top/bottom divider)
	{ key = "%", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = '"', mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	-- convenience aliases, Vim-style (v = :vsplit → left/right, s = :split → top/bottom)
	{ key = "v", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "s", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- Pane focus  (Colemak hjkl: h=up, j=left, k=down, l=right; arrows too)
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
	{ key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- Cycle to next pane  (tmux: prefix + o)
	{ key = "o", mods = "LEADER", action = act.ActivatePaneDirection("Next") },
	-- Rotate/swap panes  (tmux: prefix + { / })
	{ key = "{", mods = "LEADER", action = act.RotatePanes("CounterClockwise") },
	{ key = "}", mods = "LEADER", action = act.RotatePanes("Clockwise") },

	-- Zoom current pane  (tmux: prefix + z)
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

	-- Kill pane  (tmux: prefix + x). confirm=false keeps the original preference;
	-- tmux actually prompts y/n — flip to confirm=true to mirror that.
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = false }) },
	-- Kill window/tab  (tmux: prefix + &)
	{ key = "&", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },

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

	-- Sessions == WezTerm workspaces (the analog of a tmux session).
	-- LEADER T → picker over existing workspaces AND zoxide directories; switches to
	-- (or creates + switches to, via SwitchToWorkspace) the chosen one. This is the
	-- reliable in-GUI equivalent of tmux's `t`/`ts` — WezTerm's CLI cannot switch
	-- workspaces, so this has to happen inside the GUI.
	{ key = "T", mods = "LEADER", action = wezterm.action_callback(workspace_switcher) },
	-- LEADER S → built-in launcher: switch between EXISTING workspaces only.
	{ key = "S", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
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
					window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
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
					wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
				end
			end),
		}),
	},

	-- Repeatable resize mode  (tmux-ish): prefix + r, then hjkl/arrows, Esc to exit
	{
		key = "r",
		mods = "LEADER",
		action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false, timeout_milliseconds = 1000 }),
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

return config
