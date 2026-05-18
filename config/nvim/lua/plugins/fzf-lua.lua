return {
	{
		-- Fuzzy finder
		"ibhagwan/fzf-lua",
		-- optional for icon support
		dependencies = { "nvim-tree/nvim-web-devicons" },
		keys = {
			{
				"<C-p>",
				function()
					require("fzf-lua").files()
				end,
				mode = { "n", "i" },
				{ desc = "Fuzzy find files" },
			},
			{
				"<C-S-f>",
				function()
					require("fzf-lua").live_grep()
				end,
				mode = { "n", "i" },
				{ desc = "Fuzzy grep" },
			},
			{
				"<leader><space>",
				function()
					require("fzf-lua").files()
				end,
				mode = "n",
				{ desc = "Fuzzy find files" },
			},
			{
				"<leader>/",
				function()
					require("fzf-lua").live_grep()
				end,
				mode = "n",
				{ desc = "Fuzzy grep" },
			},
		},
		---@module "fzf-lua"
		---@type fzf-lua.Config|{}
		---@diagnostics disable: missing-fields
		opts = {
			defaults = {
				git_icons = false,
				file_icons = false,
				color_icons = false,
			},
		},
		---@diagnostics enable: missing-fields
	},
}
