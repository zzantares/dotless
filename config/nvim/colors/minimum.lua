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
		add_fg = "#597b60",
		add_bg = "#597b60",
		del_fg = "#7f605c",
		del_bg = "#7f605c",
		note = "#D3EDE7",
		warn_fg = "NvimLightYellow",
		warn_bg = "NvimLightYellow",
		err_bg = "NvimLightRed",
		on_fill = "#000000",
		visual_bg = "#888888",
		menu_bg = "#222222",
		menu_sel_bg = "#444444",
		status_bg = "#333333",
		msg_bg = "#444444",
	},

	-- The same restraint the other way up: greys carry everything, and the two
	-- accents keep their jobs. Each grey matches the contrast its dark
	-- counterpart has, measured against the terminal's light background.
	light = {
		fg = "#333333",
		fg_strong = "#262626",
		fg_bright = "#171717",
		fg_max = "#000000",
		muted = "#777777",
		dim = "#666666",
		faint = "#B0B0B0",
		question = "#888888",
		string = "#2B3328",
		accent = "#2E4C6D",
		add_fg = "#3F5E46",
		add_bg = "#CFE0CF",
		del_fg = "#7F403A",
		del_bg = "#EDD5D2",
		note = "#D3EDE7",
		-- NvimLightYellow is a fill in both, but it can only be read as text on
		-- a dark background.
		warn_fg = "NvimDarkYellow",
		warn_bg = "NvimLightYellow",
		err_bg = "NvimLightRed",
		on_fill = "#000000",
		visual_bg = "#B4B4B4",
		menu_bg = "#EDEDED",
		menu_sel_bg = "#D4D4D4",
		status_bg = "#DDDDDD",
		msg_bg = "#D4D4D4",
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

	["DiffAdd"] = { fg = "None", bg = c.add_bg, sp = "None" },
	["DiffDelete"] = { fg = "None", bg = c.del_bg },
	["DiffChange"] = { fg = "None", bg = c.warn_bg },
	["DiffText"] = { fg = c.warn_fg, bg = "None", sp = "None" },

	["Added"] = { fg = c.add_fg, bg = "None" },
	["Changed"] = { fg = c.warn_fg, bg = "None" },
	["Removed"] = { fg = c.del_fg, bg = "None" },

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

	["Search"] = { fg = c.warn_fg, bg = "None" },
	["SnippetTabstop"] = { fg = c.warn_fg, bg = "None" },

	["DiagnosticUnnecessary"] = { fg = c.dim },

	["Todo"] = { fg = c.warn_fg, bg = "None", bold = true },

	["@variable"] = { fg = c.fg },
	["@string.documentation"] = { fg = c.muted },
	["@comment.warning"] = {
		fg = c.on_fill,
		bg = c.warn_bg,
		bold = true,
	},
	["@comment.error"] = { fg = c.on_fill, bg = c.err_bg, bold = true },
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
