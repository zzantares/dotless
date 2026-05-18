-- The table returned here must be compatible to what `vim.lsp.config` expects.
-- These settings are merged with what nvim-lspconfig provides
-- see: https://github.com/neovim/nvim-lspconfig/blob/master/lsp/lua_ls.lua
return {
	settings = {
		Lua = {
			-- I prefer to do formatting via none-ls + stylua
			format = { enable = false },
			runtime = {
				-- should be set to LuaJIT when using a standard neovim build
				version = "LuaJIT",
				path = { "lua/?.lua", "lua/?/init.lua" },
			},
			-- diagnostics = {
			--     globals = { "vim" },
			-- },
			telemetry = {
				enable = false,
			},
			workspace = {
				checkThirdParty = false,
				-- When/if working on other Lua projects one might prefer to use a `.luarc.json` configuration file
				-- see: https://hugosum.com/blog/adding-types-to-your-neovim-configuration#avoid-global-configuration-with-luarcjson
				library = {
					vim.env.VIMRUNTIME,
					"$XDG_DATA_HOME/nvim/lazy",
					"${3rd}/luv/library",
				},
			},
		},
	},
}
