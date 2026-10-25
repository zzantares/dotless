-- Hand-rolled statusline, no plugin. Originally by Tanuharja, R.A. (2024-12-20).
local M = {}

M.styles = {
	statusline_file = { fg = "#EEEEEE", bg = "#333333", bold = true },
	statusline_modifiedfile = { fg = "#000000", bg = "#CCCCCC", bold = true },
	statusline_diagnostics = { fg = "#EEEEEE", bg = "#222222" },
	statusline_debugger_session = { fg = "#CCCCCC", bg = "None" },
	statusline_separator = { fg = "#333333", bg = "None" },
	statusline_misc = { fg = "#CCCCCC", bg = "None" },
	statusline_branch = { fg = "#EEEEEE", bg = "#222222" },
	statusline_mode = { fg = "#EEEEEE", bg = "#333333", bold = true },
}

-- laststatus 3 is one statusline for all windows; 0 hides it
M.laststatus = 3

local mode_aliases = {
	n = "n",
	i = "i",
	v = "v",
	V = "v",
	t = "t",
	c = "c",
	s = "s",
	[""] = "v",
}

-- gitsigns sets both buffer vars on attach; guard each, order is not promised
local function git_branch()
	local branch = vim.b.gitsigns_head
	local dict = vim.b.gitsigns_status_dict

	if branch == nil or dict == nil then
		return " -- "
	end

	return ("%%#statusline_branch# %s +%d -%d ~%d "):format(
		branch,
		dict.added or 0,
		dict.removed or 0,
		dict.changed or 0
	)
end

local function file_name()
	local filename = vim.fn.expand("%:t")
	if filename == "" then
		filename = "[no name]"
	end

	if vim.bo.buftype == "terminal" then
		filename = "terminal"
	end

	local group = vim.bo.modified and filename ~= "[no name]" and "statusline_modifiedfile" or "statusline_file"

	return ("%%#%s# %s "):format(group, filename)
end

local function current_mode()
	local mode = vim.fn.mode()
	mode = mode_aliases[mode] and mode_aliases[mode]:upper() or "?"
	return ("%%#statusline_mode# %s "):format(mode)
end

local function count(severity)
	return #vim.diagnostic.get(0, { severity = severity })
end

local function diagnostics()
	local s = vim.diagnostic.severity
	return ("%%#statusline_diagnostics# E%d W%d H%d I%d "):format(
		count(s.ERROR),
		count(s.WARN),
		count(s.HINT),
		count(s.INFO)
	)
end

-- nvim-dap is optional; without it this component is empty
local function debugger_session()
	local ok, dap = pcall(require, "dap")
	if not ok or dap.session() == nil then
		return ""
	end
	return ("%%#statusline_debugger_session# %s "):format(dap.session().config.name)
end

local function search_position()
	local ok, result = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 500 })
	if not ok or result.total == nil or result.total == 0 then
		return ""
	end
	return ("%%#statusline_misc# %s [%d/%d] "):format(vim.fn.getreg("/"), result.current, result.total)
end

local function miscellaneous()
	local reg = vim.fn.reg_recording()
	if reg == "" then
		return search_position()
	end
	return ("%%#statusline_misc# recording @%s "):format(reg)
end

function M.render()
	return table.concat({
		file_name(),
		diagnostics(),
		debugger_session(),
		"%#statusline_separator#%=",
		miscellaneous(),
		git_branch(),
		current_mode(),
	})
end

function M.setup(opts)
	opts = opts or {}
	local styles = vim.tbl_deep_extend("force", M.styles, opts.styles or {})
	local laststatus = opts.laststatus or M.laststatus

	-- :colorscheme clears highlights, so re-apply on every change
	local function paint()
		for group, style in pairs(styles) do
			vim.api.nvim_set_hl(0, group, style)
		end
	end

	local group = vim.api.nvim_create_augroup("DotlessStatusline", { clear = true })

	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = paint })
	paint()

	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = group,
		callback = function()
			vim.opt_local.cursorline = true
		end,
	})

	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		group = group,
		callback = function()
			vim.opt_local.cursorline = false
		end,
	})

	vim.o.laststatus = laststatus
	vim.o.statusline = "%!v:lua.require'dotless.statusline'.render()"

	vim.keymap.set("n", "<leader>s", function()
		vim.o.laststatus = vim.o.laststatus == 0 and laststatus or 0
	end, { desc = "Toggle the statusline" })
end

return M
