return {
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		lazy = true,
	},
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate", -- Ensure parsers are built
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
		},
		main = "nvim-treesitter.config",
		opts = {
			ensure_installed = {
				"c",
				"lua",
				"vim",
				"vimdoc",
				"query",
				"haskell",
				"json",
				"yaml",
				"toml",
				"typescript",
			},
			auto_install = true,
			textobjects = { enable = true },
			highlight = { enable = true },
			indent = { enable = true },
		},
	},
}
