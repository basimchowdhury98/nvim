local map = vim.keymap.set

map("x", "D", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
map("x", "U", ":m '<-2<CR>gv=gv", { desc = "Move slected line up" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "" })
map("n", "N", "Nzzzv", { desc = "" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Previous diagnostic" })
map("n", "<leader>dd", vim.diagnostic.open_float, { desc = "Opens float with all diags in buffer" })
map('v', 'J', 'j', { remap = true, desc = 'Remapped J to j to stop merging line under on accident' })

map('n', '<leader>kp', function()
    local path = vim.fn.expand('%:p')
    vim.fn.setreg('+', path) -- system clipboard
    vim.fn.setreg('"', path) -- default yank register
end, { desc = "Copy current buffer path" })


map({ 'n', 't' }, '<Esc><Esc>', function() vim.cmd('fclose!') end, { desc = 'Close floating windows' })

-- Buffer
map({ "n" }, "<leader>a", "ggVG", { desc = "[A]ll select" })
map({ "n" }, "<leader>/", ":noh<CR>", { desc = "Clear hl" })
map({ 'i', 't' }, '<C-BS>', '<C-w>', { desc = 'Delete by word (remapped because other apps will close with c-w)' })

-- Quick fix
map("n", "<leader>qc", ":cclose<CR>", { desc = "Close quickfix" })

-- Splits
map("n", "<leader>\\", ":vsplit<CR>", { desc = "Open vertical split" })
map("n", "<leader>-", ":split<CR>", { desc = "Open horizontal split" })
map("n", "<C-Left>", ":vertical resize +2<CR>", { desc = "Decrease split width" })
map("n", "<C-Right>", ":vertical resize -2<CR>", { desc = "Increase split width" })
map("n", "<C-Down>", ":resize +2<CR>", { desc = "Decrease split height" })
map("n", "<C-Up>", ":resize -2<CR>", { desc = "Increase split height" })

-- Lsp - rest in telescope.lua
map("n", "grd", "<C-]>", { desc = "[G]o [R]ight to [D]efinition", remap = true })
map("n", "grq", vim.lsp.buf.format, { desc = "Format" })

-- Testing
map("n", "<leader>x", "<cmd>.lua<CR>", { desc = "Execute the current line" })
map("n", "<leader><leader>x", "<cmd>source %<CR>", { desc = "Execute the current file" })
