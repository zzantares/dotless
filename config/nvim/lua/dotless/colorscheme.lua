local M = {}

M.name = "minimum"

function M.setup(opts)
	opts = opts or {}
	local name = opts.name or M.name

	-- Nvim sets 'background' from the terminal's reported background color: at
	-- startup, on resume, and - where the terminal supports DEC mode 2031 - the
	-- moment the terminal's own theme changes. Reload so the colorscheme sees it.
	local group = vim.api.nvim_create_augroup("DotlessColorscheme", { clear = true })

	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "background",
		-- `nested`, or the reload fires no ColorScheme and everything that
		-- repaints on it (the statusline) keeps the old palette.
		nested = true,
		callback = function()
			vim.cmd.colorscheme(name)
		end,
	})

	-- The terminal's answer can land after this file runs, and detection during
	-- startup fires no OptionSet, so re-apply once startup is over.
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		once = true,
		nested = true,
		callback = function()
			vim.cmd.colorscheme(name)
		end,
	})

	vim.cmd.colorscheme(name)
end

return M
