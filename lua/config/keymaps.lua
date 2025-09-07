vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
local map = vim.keymap.set

map("n", "<leader>e", vim.cmd.Ex)
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
map("n", "<leader>y", "\"+y")
map("v", "<leadery", "\"+y")

local builtin = require('telescope.builtin')
map('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
map('n', '<leader>fg', builtin.git_files, {})
map('n', '<leader>fs', builtin.live_grep, {})

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")
map("n", "<leader>a", mark.add_file)
map("n", "<leader>h", ui.toggle_quick_menu)
map("n", "<C-j>", function() ui.nav_file(1) end)
map("n", "<C-k>", function() ui.nav_file(2) end)
map("n", "<C-l>", function() ui.nav_file(3) end)
map("n", "K", vim.lsp.buf.hover, {})
