local map = vim.keymap.set

-- mini.files keyed like dired and netrw: `o` opens, `u` goes up, <Tab> expands
-- or contracts. See dotless/keymap.lua and doom's config.el
local sidebar = {}

local function files()
	return require("mini.files")
end

sidebar.toggle = function()
	if files().close() then
		return
	end

	-- open at the current file so the sidebar tracks the buffer
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" or vim.uv.fs_stat(path) == nil then
		path = vim.fn.getcwd()
	end
	files().open(path, true)
end

sidebar.open_at_point = function()
	files().go_in({ close_on_file = true })
end

-- there is no go_out_plus() in the API, only a mapping of that name
sidebar.go_up = function()
	files().go_out()
	files().trim_right()
end

-- a dir is expanded when it is the branch entry just past the focused one
local function is_expanded(state, entry)
	return entry.fs_type == "directory" and state.branch[state.depth_focus + 1] == entry.path
end

sidebar.toggle_at_point = function()
	local state, entry = files().get_explorer_state(), files().get_fs_entry()
	if state == nil or entry == nil then
		return
	end

	if entry.fs_type ~= "directory" then
		return sidebar.go_up() -- on a file, contract the parent
	end

	if is_expanded(state, entry) then
		return files().trim_right()
	end

	-- expand without following, the way treemacs TAB does
	local branch = vim.list_slice(state.branch, 1, state.depth_focus)
	table.insert(branch, entry.path)
	files().set_branch(branch, { depth_focus = state.depth_focus })
end

-- CRUD goes through the buffer so mini.files shows its confirmation and keeps
-- trash, open buffers and LSP in step

-- it counts TextChanged to spot a dirty buffer, and API writes fire none; two
-- events clear the -1 it sets after every render
local function sync(buf)
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	files().synchronize()
end

sidebar.create = function()
	local name = vim.fn.input("Create (trailing / makes a dir): ")
	if name == "" then
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { name })
	sync(buf)
end

sidebar.delete = function()
	if files().get_fs_entry() == nil then
		return
	end

	local buf, line = vim.api.nvim_get_current_buf(), vim.fn.line(".")
	vim.api.nvim_buf_set_lines(buf, line - 1, line, false, {})
	sync(buf)
end

sidebar.rename = function()
	local entry = files().get_fs_entry()
	if entry == nil then
		return
	end

	local new = vim.fn.input("Rename: ", entry.name)
	if new == "" or new == entry.name then
		return
	end

	-- keep the hidden path id, else the line reads as a brand new entry
	local buf, line = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_line()
	vim.api.nvim_set_current_line(line:sub(1, #line - #entry.name) .. new)
	sync(buf)
end

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
			local trailspace = require(plugin.name)
			trailspace.setup(opts)

			-- remove trails on save
			vim.api.nvim_create_autocmd({ "BufWritePre" }, {
				pattern = { "*" },
				callback = function()
					trailspace.trim()
					trailspace.trim_last_lines()
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
	{
		-- File explorer, navigated like a buffer
		"nvim-mini/mini.files",
		version = "*",
		keys = {
			{
				"<leader>op",
				function()
					sidebar.toggle()
				end,
				mode = "n",
				desc = "Toggle project sidebar",
			},
		},
		opts = {
			mappings = {
				-- colemak-dh: j/l are left/right, so they go out/in. `h` is
				-- left unmapped to stay cursor-up, as it is in dired
				go_in = "l",
				go_in_plus = "L",
				go_out = "j",
				go_out_plus = "J",
				-- `m` is the dired-style action prefix below
				mark_set = "gm",
			},
			options = {
				-- netrw stays the directory editor, so `<leader>tr` is untouched
				use_as_default_explorer = false,
				permanent_delete = false,
			},
			-- treemacs-width is 40 in the doom config
			windows = { width_focus = 40, width_nofocus = 20 },
		},
		config = function(plugin, opts)
			require(plugin.name).setup(opts)

			vim.api.nvim_create_autocmd("User", {
				pattern = "MiniFilesBufferCreate",
				callback = function(args)
					local buf = args.data.buf_id

					local function bmap(lhs, rhs, desc)
						map("n", lhs, rhs, { buffer = buf, desc = desc })
					end

					bmap("o", sidebar.open_at_point, "Open thing at point")
					bmap("u", sidebar.go_up, "Go up one dir")
					bmap("<Tab>", sidebar.toggle_at_point, "Expand or contract dir at point")

					for lhs, action in pairs({
						["ma"] = { sidebar.create, "Create file or dir" },
						["+"] = { sidebar.create, "Create file or dir" },
						["md"] = { sidebar.delete, "Delete thing at point" },
						["D"] = { sidebar.delete, "Delete thing at point" },
						["mm"] = { sidebar.rename, "Rename thing at point" },
						["R"] = { sidebar.rename, "Rename thing at point" },
					}) do
						bmap(lhs, action[1], action[2])
					end
				end,
			})
		end,
	},
}
