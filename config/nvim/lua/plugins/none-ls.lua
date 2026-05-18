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
			local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
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
					-- null_ls.builtins.formatting.fourmolu,
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
				-- you can reuse a shared lspconfig on_attach callback here
				on_attach = function(client, bufnr)
					if client.supports_method("textDocument/formatting") then
						vim.api.nvim_clear_autocmds({
							group = augroup,
							buffer = bufnr,
						})
						vim.api.nvim_create_autocmd("BufWritePre", {
							group = augroup,
							buffer = bufnr,
							callback = function()
								vim.lsp.buf.format({
									bufnr = bufnr,
									async = false,
								})
							end,
						})
					end
				end,
			}
		end,
	},
}
