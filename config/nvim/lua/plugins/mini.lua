return {
	{
		-- Auto close parens, brackets and other pair characters
		"nvim-mini/mini.pairs",
		version = "*",
		opts = {},
	},
	{
		-- Remove trail whitespace and lines from a buffer
		"nvim-mini/mini.trailspace",
		version = "*",
		config = function(plugin, opts)
			require(plugin.name).setup(opts)

			-- remove trails on save
			vim.api.nvim_create_autocmd({ "BufWritePre" }, {
				pattern = { "*" },
				callback = function()
					MiniTrailspace.trim()
					MiniTrailspace.trim_last_lines()
				end,
			})
		end,
	},
	{
		-- Custom highlight text patterns
		"nvim-mini/mini.hipatterns",
		version = "*",
		opts = function(plugin)
			local hipatterns = require(plugin.name)
			return {
				highlighters = {
					-- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
					fixme = {
						pattern = "%f[%w]()FIXME()%f[%W]",
						group = "MiniHipatternsFixme",
					},
					hack = {
						pattern = "%f[%w]()HACK()%f[%W]",
						group = "MiniHipatternsHack",
					},
					todo = {
						pattern = "%f[%w]()TODO()%f[%W]",
						group = "MiniHipatternsTodo",
					},
					note = {
						pattern = "%f[%w]()NOTE()%f[%W]",
						group = "MiniHipatternsNote",
					},

					-- Highlight hex color strings (`#rrggbb`) using that color
					hex_color = hipatterns.gen_highlighter.hex_color(),
				},
			}
		end,
		config = function(plugin, opts)
			require(plugin.name).setup(opts)

			-- Declares styles for the new patterns
			local styles = {
				["MiniHipatternsFixme"] = { link = "DiagnosticError" },
				["MiniHipatternsHack"] = { link = "DiagnosticWarn" },
				["MiniHipatternsTodo"] = { link = "DiagnosticInfo" },
				["MiniHipatternsNote"] = { link = "DiagnosticHint" },
			}

			for group, style in pairs(styles) do
				vim.api.nvim_set_hl(0, group, style)
			end
		end,
	},
}
