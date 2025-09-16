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
map('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

local builtin = require('telescope.builtin')
local telescope = require('telescope')
map('n', '<leader>ff', builtin.find_files, { desc = "Find all files" })
map('n', '<leader>fg', builtin.git_files, { desc = "Find git files" })
map('n', '<leader>fs', builtin.live_grep, { desc = "Find by regex/live grep" })
map('n', '<leader>ft', builtin.treesitter, { desc = "Find symbols using treesitter" })
map('n', '<leader>fr', builtin.resume, { desc = "Resume last telescope search" })
map('n', '<leader>fo', builtin.oldfiles, { desc = "Find previously opened files" })
map('n', '<leader>fk', builtin.keymaps, { desc = "Find keymaps"})
map('n', '<leader>fp', telescope.extensions.project.project, { desc = "Find projects"})

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")
map("n", "<leader>a", mark.add_file, { desc = "Add file to harpoon" })
map("n", "<leader>A", mark.clear_all, { desc = "Clear all files from harpoon" })
map("n", "<C-h>", ui.toggle_quick_menu, { desc = "Toggle harpoon menu" })
map("n", "<C-j>", function() ui.nav_file(1) end)
map("n", "<C-k>", function() ui.nav_file(2) end)
map("n", "<C-l>", function() ui.nav_file(3) end)

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('lsp-keymaps', { clear = true }),
    callback = function(event)
        map("n", "H", vim.lsp.buf.hover, { desc= "Lsp - show hover info", buffer = event.buf })
        map("n", "<leader>gd", vim.lsp.buf.definition, { desc= "Lsp - go to definition", buffer = event.buf })
        map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc= "Lsp - code actions", buffer = event.buf })
        map({ "n", "v" }, "<leader>cf", vim.lsp.buf.format, { desc= "Lsp - format code in file", buffer = event.buf })
        map({ "n", "v" }, "<leader>cr", vim.lsp.buf.rename, { desc= "Lsp - rename symbol under cursor", buffer = event.buf })
    end
})
