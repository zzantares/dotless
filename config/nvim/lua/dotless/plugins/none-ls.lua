return {
	{
		-- Make CLI tools appear as LSP providers for certain actions
		"nvimtools/none-ls.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvimtools/none-ls-extras.nvim",
		},
		main = "null-ls",
		opts = function(plugin)
			local null_ls = require(plugin.main)
			local h = require("null-ls.helpers")

			-- HLS formats with its bundled fourmolu, which takes extensions
			-- from the cabal file and so chokes on syntax the project does
			-- not declare. Shell out to the CLI with the same flags the
			-- Emacs config passes.
			local fourmolu = h.make_builtin({
				name = "fourmolu",
				meta = {
					url = "https://github.com/fourmolu/fourmolu",
					description = "A formatter for Haskell source code.",
				},
				method = null_ls.methods.FORMATTING,
				filetypes = { "haskell" },
				generator_opts = {
					command = "fourmolu",
					args = {
						"--ghc-opt",
						"-XImportQualifiedPost",
						"--ghc-opt",
						"-XBangPatterns",
						"--stdin-input-file",
						"$FILENAME",
					},
					to_stdin = true,
				},
				factory = h.formatter_factory,
			})

			return {
				sources = {
					require("none-ls.formatting.rustfmt"),
					null_ls.builtins.diagnostics.ansiblelint,
					null_ls.builtins.diagnostics.hadolint,
					-- null_ls.builtins.diagnostics.sqlfluff.with({
					--     extra_args = { "--dialect", "postgres" }, -- change to your dialect
					-- }),
					-- null_ls.builtins.diagnostics.tsc,
					null_ls.builtins.diagnostics.zsh,
					-- null_ls.builtins.diagnostics.selene, -- Lua diagnostics
					null_ls.builtins.formatting.stylua.with({
						extra_args = {
							"--indent-type",
							"Spaces",
							"--indent-width",
							"4",
							"--line-endings",
							"Unix",
							"--quote-style",
							"ForceDouble",
							"--column-width",
							"80",
							"--sort-requires",
						},
					}),
					-- null_ls.builtins.formatting.cabal_fmt,
					null_ls.builtins.formatting.biome,
					null_ls.builtins.formatting.clang_format,
					-- builtins.formatting.fourmolu no longer ships with
					-- none-ls, hence the local source defined above
					fourmolu,
					null_ls.builtins.formatting.hclfmt,
					null_ls.builtins.formatting.just,
					null_ls.builtins.formatting.nixfmt,
					null_ls.builtins.formatting.shfmt,
					null_ls.builtins.formatting.pg_format,
					-- null_ls.builtins.formatting.sqlfluff.with({
					--     extra_args = { "--dialect", "postgres" }, -- change to your dialect
					-- }),
					null_ls.builtins.formatting.terraform_fmt,
					null_ls.builtins.formatting.opentofu_fmt.with({
						filetypes = { "opentofu" },
					}),
				},
			}
		end,
	},
}
