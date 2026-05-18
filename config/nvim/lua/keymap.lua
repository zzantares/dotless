local map = vim.keymap.set

-- Navigation (colemak)
map({ "n", "v" }, "h", "<Up>")
map({ "n", "v" }, "k", "<Down>")
map({ "n", "v" }, "j", "<Left>")
map({ "n", "v" }, "l", "<Right>")

map("n", "<C-w><C-k>", "<C-w><C-j>")
map("n", "<C-w><C-j>", "<C-w><C-h>")
map("n", "<C-w><C-h>", "<C-w><C-k>")
map("n", "<C-w>k", "<C-w>j")
map("n", "<C-w>j", "<C-w>h")
map("n", "<C-w>h", "<C-w>k")

-- Handles visual lines
map({ "n", "v" }, "gj", "gk", { remap = true })
map({ "n", "v" }, "gk", "gh", { remap = true })

-- Improved builtins
map("i", "<C-f>", "<Right>")
map("n", "<leader>qq", ":quitall<cr>")
map("n", "<M-,>", ":e $MYVIMRC<cr>")
map("n", "<leader>tr", ":e .<cr>")
map("n", "<leader>tt", ":Explore<cr>")
map("n", "<C-s>", ":update<cr>")
map("i", "<C-s>", "<Esc>:update<cr>")
map("n", "<leader>bk", ":bdelete<cr>")
map("n", "gb", "<C-^>")

-- FIXME these are deprecated but the alternatives I just commented out do not work
map("n", "]e", vim.diagnostic.goto_next)
map("n", "[e", vim.diagnostic.goto_prev)
-- vim.keymap.set("n", "]e", vim.diagnostic.jump({ count = 1, float = true }))
-- vim.keymap.set("n", "[e", vim.diagnostic.jump({ count = -1, float = true }))
--

local autocmd = vim.api.nvim_create_autocmd

autocmd("FileType", {
	pattern = "netrw",
	callback = function()
		map("n", "q", ":bd<cr>", {
			buffer = true,
			desc = "Quits the file explorer",
		})
		map("n", "o", "<cr>", {
			buffer = true,
			remap = true,
			desc = "Open thing at point",
		})
		map("n", "gb", "<C-^>", {
			buffer = true,
			remap = true,
			desc = "Go back",
		})
		map("n", "u", "-", {
			buffer = true,
			remap = true,
			desc = "Go up one dir",
		})
		map("n", "+", "d", {
			buffer = true,
			remap = true,
			desc = "Make directory",
		})
	end,
})

autocmd("FileType", {
	pattern = "help",
	callback = function()
		map("n", "q", ":q<cr>", {
			buffer = true,
			desc = "Quit help",
		})
	end,
})
