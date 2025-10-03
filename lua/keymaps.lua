local map = vim.keymap.set

map("n", "<leader>e", vim.cmd.Ex, { desc = "Open netrw/file explorer" })
map("v", "D", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
map("v", "U", ":m '<-2<CR>gv=gv", { desc = "Move slected line up" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "" })
map("n", "N", "Nzzzv", { desc = "" })
map({ "n", "v" }, "<leader>y", "\"+y", { desc = "Copy to system clipboard" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
map("n", "<leader>dd", vim.diagnostic.open_float, { desc = "Opens float with all diags in buffer" })
map('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
map('n', '<leader>cc', 'gcc', { remap = true, desc = 'Comment line' })
map('v', '<leader>cc', 'gc', { remap = true, desc = 'Comment selection' })
map('v', 'J', 'j', { remap = true, desc = 'Remapped J to j to stop merging line under on accident' })
map('x', "<leader>p", "\"_dP", { desc = "Paste without copying whats pasted over" })

map('n', '<leader>kp', function()
    local path = vim.fn.expand('%:p')
    vim.fn.setreg('+', path) -- system clipboard
    vim.fn.setreg('"', path) -- default yank register
end, { desc = "Copy current buffer path" })

map('n', '<Esc><Esc>', function()
    for _, win in pairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' then -- floating window
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = 'Close floating windows' })

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")
map("n", "<leader>a", mark.add_file, { desc = "Add file to harpoon" })
map("n", "<C-h>", ui.toggle_quick_menu, { desc = "Toggle harpoon menu" })
map("n", "<C-j>", function() ui.nav_file(1) end, { desc = "Navigate to file 1" })
map("n", "<C-k>", function() ui.nav_file(2) end, { desc = "Navigate to file 2" })
map("n", "<C-n>", function() ui.nav_file(3) end, { desc = "Navigate to file 3" })
map("n", "<C-m>", function() ui.nav_file(4) end, { desc = "Navigate to file 4" })

local terminal = require('utils.terminal')
map('n', '<leader>tt', terminal.toggle, { desc = "Toggle the floating terminal" })
map({ 't', 'n' }, '<Esc><Esc>', terminal.close, { desc = "Close the floating terminal" })
map('n', '<leader>tk', terminal.kill, { desc = "Kill the floating terminal" })
