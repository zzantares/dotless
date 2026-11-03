return {
	{
		-- Lean 4, infoview included. nvim-lspconfig ships only a Lean 3
		-- server. This plugin owns the Lean 4 one and enables it itself. Its
		-- `lsp/leanls.lua` runs `lake serve`, so all it needs is
		-- `toolchains.lean` on PATH.
		"Julian/lean.nvim",
		-- `init`, not `opts`: upstream dropped `setup()`, and its ftplugin
		-- self-activates, so the global must be set before a .lean buffer.
		init = function()
			vim.g.lean_config = {
				mappings = true,
			}
		end,
	},
}
