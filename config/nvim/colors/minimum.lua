---
-- @file colors/minimum.lua
--
-- @brief
-- A minimum colorscheme
--
-- @author Tanuharja, R.A.
-- @date 2024-12-20
--
-- Backgrounds stay "None" so the terminal's own palette shows through. The
-- literals are named below and swapped on 'background', which Nvim sets from
-- the terminal's reported background color.
--

local palettes = {
	dark = {
		fg = "#CCCCCC",
		fg_strong = "#DDDDDD",
		fg_bright = "#EEEEEE",
		fg_max = "#FFFFFF",
		muted = "#777777",
		dim = "#888888",
		faint = "#444444",
		question = "#666666",
		string = "#D6DFD4",
		accent = "#87AFD7",
		add = "#597b60",
		delete = "#7f605c",
		note = "#D3EDE7",
		on_fill = "#000000",
		visual_bg = "#888888",
		menu_bg = "#222222",
		menu_sel_bg = "#444444",
		status_bg = "#333333",
		msg_bg = "#444444",
	},

	-- Solarized Light: base00 body text, base01 emphasis, base1 comments,
	-- base2 fills, and Solarized's own accents.
	light = {
		fg = "#657b83",
		fg_strong = "#586e75",
		fg_bright = "#586e75",
		fg_max = "#002b36",
		muted = "#93a1a1",
		dim = "#93a1a1",
		faint = "#eee8d5",
		question = "#839496",
		string = "#2aa198",
		accent = "#268bd2",
		add = "#859900",
		delete = "#dc322f",
		note = "#d3ede7",
		on_fill = "#002b36",
		visual_bg = "#93a1a1",
		menu_bg = "#eee8d5",
		menu_sel_bg = "#93a1a1",
		status_bg = "#eee8d5",
		msg_bg = "#eee8d5",
	},
}

local c = palettes[vim.o.background] or palettes.dark

local group_styles = {

	["Normal"] = { fg = c.fg, bg = "None" },
	["NormalFloat"] = { fg = c.fg, bg = "None" },

	["String"] = { fg = c.string },
	["Comment"] = { fg = c.muted },

	["Visual"] = { fg = c.on_fill, bg = c.visual_bg },

	["Identifier"] = { fg = c.fg_strong, bold = true },
	["Statement"] = { fg = c.fg_bright, bold = true },
	["Special"] = { fg = c.accent, bold = false },

	["Function"] = { fg = c.accent },
	["Constant"] = { fg = c.fg },

	["DiffAdd"] = { fg = "None", bg = c.add, sp = "None" },
	["DiffDelete"] = { fg = "None", bg = c.delete },
	["DiffChange"] = { fg = "None", bg = "NvimLightYellow" },
	["DiffText"] = { fg = "NvimLightYellow", bg = "None", sp = "None" },

	["Added"] = { fg = c.add, bg = "None" },
	["Changed"] = { fg = "NvimLightYellow", bg = "None" },
	["Removed"] = { fg = c.delete, bg = "None" },

	["Error"] = { fg = c.fg_max, bg = "None", bold = true },

	["QuickFixLine"] = { fg = c.fg, bold = true },

	["Pmenu"] = { fg = c.fg_strong, bg = c.menu_bg },
	["PmenuSel"] = { fg = c.fg, bg = c.menu_sel_bg },

	["Question"] = { fg = c.question },
	["Directory"] = { fg = c.muted },

	["MsgSeparator"] = { fg = c.fg_bright, bg = c.msg_bg },
	["MoreMsg"] = { fg = c.fg_bright, bg = c.msg_bg },

	["StatusLine"] = { fg = c.fg_bright, bg = c.status_bg },

	["Folded"] = { fg = c.faint },
	["MatchParen"] = { fg = c.fg_max, bold = true },
	["WinSeparator"] = { fg = c.faint },

	["Search"] = { fg = "NvimLightYellow", bg = "None" },
	["SnippetTabstop"] = { fg = "NvimLightYellow", bg = "None" },

	["DiagnosticUnnecessary"] = { fg = c.dim },

	["Todo"] = { fg = "NvimLightYellow", bg = "None", bold = true },

	["@variable"] = { fg = c.fg },
	["@string.documentation"] = { fg = c.muted },
	["@comment.warning"] = {
		fg = c.on_fill,
		bg = "NvimLightYellow",
		bold = true,
	},
	["@comment.error"] = { fg = c.on_fill, bg = "NvimLightRed", bold = true },
	["@comment.note"] = { fg = c.on_fill, bg = c.note, bold = true },

	["LspSignatureActiveParameter"] = { bg = "None" },
	["LspReferenceTarget"] = { bg = "None" },

	["NvimTreeGitDeletedIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitDirtyIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitIgnoredIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitMergeIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitNewIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitRenamedIcon"] = { fg = c.accent, bg = "None" },
	["NvimTreeGitStagedIcon"] = { fg = c.accent, bg = "None" },
}

for group, style in pairs(group_styles) do
	vim.api.nvim_set_hl(0, group, style)
end
