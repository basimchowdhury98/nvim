local map = vim.keymap.set

map("v", "D", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
map("v", "U", ":m '<-2<CR>gv=gv", { desc = "Move slected line up" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "" })
map("n", "N", "Nzzzv", { desc = "" })
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

local terminal = require('utils.terminal')
map('n', '<leader>to', terminal.open, { desc = "Open the floating terminal" })
map({ 't', 'n' }, '<Esc><Esc>', terminal.close, { desc = "Close the floating terminal" })
map('n', '<leader>tk', terminal.kill, { desc = "Kill the floating terminal" })
map('n', '<leader>tn', terminal.open_new_terminal, { desc = "Open a new terminal" })
map('n', '<leader>td', terminal.debug, { desc = "Debug" })
map('t', '<M-o>', terminal.open_new_terminal, { desc = "Open a new terminal" })
map('t', '<M-n>', terminal.next, { desc = "Next terminal" })
map('t', '<M-p>', terminal.prev, { desc = "Next terminal" })

map("i", "<C-l>", "<Esc>la", { desc = "Move one char left in insert mode" })
map("i", "<S-CR>", "<Esc>$o", { desc = "From anywhere in line enter into a new line in insert mode" })

-- Buffer
map({ "i" }, "jk", "<C-c>", { desc = "[E]xit from insert to normal mode", remap = true })
map({ "t" }, "jk", "<Esc>", { desc = "[E]xit from terminal to normal mode", remap = true })
map({ "i" }, "JK", "<C-c>", { desc = "[E]xit from insert to normal mode", remap = true })
map({ "t" }, "JK", "<Esc>", { desc = "[E]xit from terminal to normal mode", remap = true })

-- Quick fix
map("n", "<leader>qc", ":cclose<CR>", { desc = "Close quickfix" })

-- Splits
map("n", "<C-h>", "<C-w>h", { desc = "Nav to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Nav to down split" })
map("n", "<C-k>", "<C-w>k", { desc = "Nav to up split" })
map("n", "<C-l>", "<C-w>l", { desc = "Nav to right split" })
map("n", "<M-\\>", ":vsplit<CR>", { desc = "Open vertical split" })
map("n", "<M-->", ":split<CR>", { desc = "Open horizontal split" })
