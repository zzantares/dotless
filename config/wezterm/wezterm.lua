local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

-- Workspace switcher: zoxide + fzf picker that creates or switches to a
-- workspace named after the chosen directory (git root when possible).
local function workspace_switcher(window, pane)
  local home = os.getenv("HOME") or ""

  -- Build a list: existing workspaces first, then zoxide directories
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
        -- Show path relative to $HOME when possible
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

        -- Derive workspace name: use git root basename if available, else directory basename
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
  { key = "t", mods = "SUPER", action = wezterm.action_callback(workspace_switcher) },
  -- Quick access to the built-in workspace list (no zoxide, just existing workspaces)
  { key = "w", mods = "SUPER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
}

return config
