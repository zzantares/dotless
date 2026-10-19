return {
	{
		-- GitHub PR review: inline comments, suggestions, approve/request changes
		"pwntester/octo.nvim",
		cmd = "Octo",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"ibhagwan/fzf-lua",
			"nvim-tree/nvim-web-devicons",
		},
		opts = {
			picker = "fzf-lua",

			-- Read the right-hand side of a review from the working tree rather
			-- than from fetched blobs. `pr-review` runs nvim inside the worktree
			-- `git pr` checked out at the PR head, so this is the same file `o`
			-- opens from diffnav - editable, and lsp/treesitter see a real file.
			-- A force-push after checkout drifts it; re-running `R` refetches.
			use_local_fs = true,
		},
	},
}
