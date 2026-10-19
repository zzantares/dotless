-- These are extra settings to be merged with what nvim-lspconfig provides
-- see: https://github.com/neovim/nvim-lspconfig/blob/master/lsp/jsonls.lua
return {
	settings = {
		json = {
			schemas = require("schemastore").json.schemas(),
			format = { enable = false },
			validate = { enable = true },
		},
	},
}
