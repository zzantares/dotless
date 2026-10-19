local M = {}

-- This file is lua/dotless/lazy.lua, so the tree root is three levels up.
M.root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"))

-- lazy.nvim resets the runtimepath, dropping what init.lua prepended. Its own
-- `rtp.paths` append past `after/`, so prepend again: `ftplugin/` and `lsp/`
-- files in ~/.config/nvim and its `after/` keep winning over dotless's.
function M.restore_rtp()
	if not vim.tbl_contains(vim.opt.rtp:get(), M.root) then
		vim.opt.rtp:prepend(M.root)
	end
end

-- Every dotless plugin spec, in the order lazy.nvim imports them. Pass a
-- `spec` to M.setup to replace the list; add `{ import = "..." }` entries or a
-- repeated plugin with new `opts` to extend it (lazy deep-merges `opts`).
M.specs = {
	{ import = "dotless.plugins.base" },
	{ import = "dotless.plugins.fzf-lua" },
	{ import = "dotless.plugins.mini" },
	{ import = "dotless.plugins.none-ls" },
	{ import = "dotless.plugins.octo" },
	{ import = "dotless.plugins.treesitter" },
}

M.opts = {
	checker = { enabled = false, notify = false },
	change_detection = { enabled = true, notify = false },
}

-- Clone lazy.nvim on first run; it updates itself from then on.
local function bootstrap()
	local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

	if not (vim.uv or vim.loop).fs_stat(lazypath) then
		local lazyrepo = "https://github.com/folke/lazy.nvim.git"
		local out = vim.fn.system({
			"git",
			"clone",
			"--filter=blob:none",
			"--branch=stable",
			lazyrepo,
			lazypath,
		})
		if vim.v.shell_error ~= 0 then
			vim.api.nvim_echo({
				{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
				{ out, "WarningMsg" },
				{ "\nPress any key to exit..." },
			}, true, {})
			vim.fn.getchar()
			os.exit(1)
		end
	end

	vim.opt.rtp:prepend(lazypath)
end

function M.setup(opts)
	opts = opts or {}
	bootstrap()

	-- Set before lazy loads, so mappings declared in specs resolve correctly.
	vim.g.mapleader = " "
	vim.g.maplocalleader = "\\"

	local config = vim.tbl_deep_extend("force", M.opts, opts)
	config.spec = opts.spec or M.specs

	require("lazy").setup(config)
	M.restore_rtp()
end

return M
