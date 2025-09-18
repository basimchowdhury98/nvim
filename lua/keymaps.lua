local map = vim.keymap.set

map("n", "<leader>e", vim.cmd.Ex, { desc = "Open netrw/file explorer" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move slected line up" })
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
map('n', '<leader>kp', function()
    local path = vim.fn.expand('%:p')
    vim.fn.setreg('+', path) -- system clipboard
    vim.fn.setreg('"', path) -- default yank register
end, { desc = "Copy current buffer path" })

local builtin = require('telescope.builtin')
local telescope = require('telescope')
map('n', '<leader>ff', builtin.find_files, { desc = "Find all files" })
map('n', '<leader>fg', builtin.git_files, { desc = "Find git files" })
map('n', '<leader>fs', builtin.live_grep, { desc = "Find by regex/live grep" })
map('n', '<leader>ft', builtin.treesitter, { desc = "Find symbols using treesitter" })
map('n', '<leader>fr', builtin.resume, { desc = "Resume last telescope search" })
map('n', '<leader>fo', builtin.oldfiles, { desc = "Find previously opened files" })
map('n', '<leader>fk', builtin.keymaps, { desc = "Find keymaps" })
map('n', '<leader>fp', telescope.extensions.project.project, { desc = "Find projects" })
map('n', '<leader>fb', ':Telescope file_browser<CR>', { desc = "Open telescope file browser" })

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")
map("n", "<leader>a", mark.add_file, { desc = "Add file to harpoon" })
map("n", "<C-h>", ui.toggle_quick_menu, { desc = "Toggle harpoon menu" })
map("n", "<C-j>", function() ui.nav_file(1) end, { desc = "Navigate to file 1" })
map("n", "<C-k>", function() ui.nav_file(2) end, { desc = "Navigate to file 2" })
map("n", "<C-n>", function() ui.nav_file(3) end, { desc = "Navigate to file 3" })
map("n", "<C-m>", function() ui.nav_file(4) end, { desc = "Navigate to file 4" })

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('lsp-keymaps', { clear = true }),
    callback = function(event)
        map("n", "H", vim.lsp.buf.hover, { desc = "Lsp - show hover info", buffer = event.buf })
        map("n", "<leader>gd", vim.lsp.buf.definition, { desc = "Lsp - go to definition", buffer = event.buf })
        map("n", "<leader>gi", vim.lsp.buf.implementation, { desc = "Lsp - go to definition", buffer = event.buf })
        map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Lsp - code actions", buffer = event.buf })
        map({ "n", "v" }, "<leader>cf", vim.lsp.buf.format, { desc = "Lsp - format code in file", buffer = event.buf })
        map({ "n", "v" }, "<leader>cr", vim.lsp.buf.rename, { desc = "Lsp - rename symbol under cursor", buffer = event.buf })
    end
})

local terminal = require('utils.terminal')
map('n', '<leader>tt', terminal.toggle, { desc = "Toggle the floating terminal" })
map({ 't', 'n' }, '<Esc><Esc>', terminal.close, { desc = "Close the floating terminal" })
map('n', '<leader>tk', terminal.kill, { desc = "Kill the floating terminal" })
