vim.cmd.colorscheme("minimum")

require("options")
require("keymap")

vim.diagnostic.config({
	virtual_text = true,
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = false,
})

-- == Plugins
--
require("config.lazy") -- Loads the config/lazy.lua file

-- While we migrate config to Lua we need to source legacy migration
-- vim.cmd("source" .. vim.fn.stdpath("config") .. "/legacy-configuration.vim")

-- TODO Migrate from vim-plug to lazy.nvim plugin manager

-- Force autocmds on FileType to be available
-- vim.api.nvim_exec_autocmds("FileType", {})

-- Enable LSP servers (makes neovim source `lsp/*.lua` files)
-- they are merged with what nvim-lspconfig provides given that
-- they are named the same.
-- For a complete comentary of Nvim + LSP see: https://dev.to/vonheikemen/a-guide-on-neovims-lsp-client-mn0
vim.lsp.enable("lua_ls")
vim.lsp.enable("jsonls")
vim.lsp.enable("tofu_ls")
vim.lsp.enable("nixd")
vim.lsp.enable("bashls")

vim.filetype.add({
	extension = {
		tofu = "opentofu",
	},
	pattern = {
		[".*.nomad.tftpl"] = "hcl",
	},
})

-- FIXME should be in ftplugin/opentofu.lua but it doesn't run it?
vim.api.nvim_create_autocmd("FileType", {
	pattern = "opentofu",
	callback = function()
		vim.opt_local.syntax = "terraform"
	end,
})

-- vim.lsp.diagnostics.enable()
