return {
	{
		-- Lean 4, infoview included. nvim-lspconfig ships only a Lean 3
		-- server. This plugin owns the Lean 4 one and enables it itself. Its
		-- `lsp/leanls.lua` runs `lake serve`, so all it needs is
		-- `toolchains.lean` on PATH.
		"Julian/lean.nvim",
		opts = {
			mappings = true,
		},
	},
}
