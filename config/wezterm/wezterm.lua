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

-- Key bindings
config.leader = { key = "t", mods = "CTRL", timeout_milliseconds = 1000 }

-- Workspace switcher: zoxide + fzf picker that creates or switches to a
-- workspace named after the chosen directory (git root when possible).
local function workspace_switcher(window, pane)
	local home = os.getenv("HOME") or ""

	local script = [[
    printf '=== workspaces ===\n'
    wezterm cli list --format json 2>/dev/null \
      | grep -o '"workspace":"[^"]*"' \
      | sed 's/"workspace":"//;s/"$//' \
      | sort -u
    printf '=== directories ===\n'
    zoxide query -l 2>/dev/null
  ]]

	local success, stdout, stderr = wezterm.run_child_process({ "bash", "-c", script })
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
					wezterm.run_child_process({ "git", "-C", id, "rev-parse", "--show-toplevel" })
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
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = false }) },
	{ key = "s", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "v", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "t", mods = "LEADER", action = wezterm.action_callback(workspace_switcher) },
}

return config
