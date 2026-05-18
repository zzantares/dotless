-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- better up/down
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gj' : '<Down>'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'k'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "h", "v:count == 0 ? 'gk' : '<Up>'", { desc = "Up", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'h'", { desc = "Up", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "j", "<Left>", { desc = "Left", silent = true })
vim.keymap.set({ "n", "x" }, "l", "<Right>", { desc = "Right", silent = true })

-- Move to window using the <ctrl> hjkl keys
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to Left Window", remap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to Lower Window", remap = true })
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to Upper Window", remap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", remap = true })

-- Move Lines
vim.keymap.set("n", "<A-k>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
vim.keymap.set("n", "<A-h>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
vim.keymap.set("i", "<A-k>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
vim.keymap.set("i", "<A-h>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
vim.keymap.set("v", "<A-k>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
vim.keymap.set("v", "<A-h>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })
