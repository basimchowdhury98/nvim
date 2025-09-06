vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
local map = vim.keymap.set

map("n", "<leader>e", vim.cmd.Ex)

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

