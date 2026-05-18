local g = vim.g
local o = vim.opt

g.mapleader = " "

o.termguicolors = true
o.cursorline = false -- highlight current line
o.winborder = "single"
o.showtabline = 0
o.inccommand = "split"
o.splitright = true
o.splitbelow = true
o.autoread = true
o.confirm = true

o.hidden = true
o.showmode = false
o.lazyredraw = true
o.ttyfast = true
o.signcolumn = "yes:1"
o.ignorecase = true
o.smartcase = true
o.smartindent = true

-- default indentation options
o.tabstop = 4
o.shiftwidth = 4
o.expandtab = true

-- o.completeopt = "preview"

-- o.fileencoding = "utf-8" -- TODO causes a "modifiable is off" error
-- g.vim_json_syntax_conceal = 0
