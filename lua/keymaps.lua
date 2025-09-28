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

local builtin = require('telescope.builtin')
local telescope = require('telescope')
map('n', '<leader>ff', builtin.find_files, { desc = "[F]ind all [F]iles" })
map('n', '<leader>fg', builtin.git_files, { desc = "[F]ind [G]it files" })
map('n', '<leader>fS', builtin.live_grep, { desc = "[F]ind by [S]earch(capital) using grep" })
map('n', '<leader>fr', builtin.resume, { desc = "[F]ind [R]esume" })
map('n', '<leader>fk', builtin.keymaps, { desc = "[F]ind [K]eymaps" })
map('n', '<leader>fp', telescope.extensions.project.project, { desc = "[F]ind [P]roject" })
map('n', '<leader>fh', builtin.help_tags, { desc = "[F]ind in [H]elp" })
map('n', '<leader>fo', builtin.buffers, { desc = "[F]ind [O]pen buffers" })
map('n', '<leader>fc', builtin.colorscheme, { desc = "[F]ind [C]olorscheme" })
vim.keymap.set('n', '<leader>fj', function()
    -- Setting custom style for searching within a file
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        previewer = false,
    })
end, { desc = '[F]ind in [J]ust this file' })
vim.keymap.set('n', '<leader>fn', function()
    builtin.find_files {
        cwd = vim.fn.stdpath 'config',
        prompt_title = 'Find in Neovim Config'
    }
end, { desc = '[F]ind in [N]eovim config' })
vim.keymap.set('n', '<leader>fs', function()
    builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Grep Open Files',
    }
end, { desc = '[F]ind by [S]earching open files' })

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
        map("n", "<leader>gr", vim.lsp.buf.references, { desc = "Lsp - list all references", buffer = event.buf })
        map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Lsp - code actions", buffer = event.buf })
        map({ "n", "v" }, "<leader>cf", vim.lsp.buf.format, { desc = "Lsp - format code in file", buffer = event.buf })
        map({ "n", "v" }, "<leader>cr", vim.lsp.buf.rename, { desc = "Lsp - rename symbol under cursor", buffer = event.buf })
    end
})

local terminal = require('utils.terminal')
map('n', '<leader>tt', terminal.toggle, { desc = "Toggle the floating terminal" })
map({ 't', 'n' }, '<Esc><Esc>', terminal.close, { desc = "Close the floating terminal" })
map('n', '<leader>tk', terminal.kill, { desc = "Kill the floating terminal" })


local ls = require("luasnip")
vim.keymap.set({"i", "s"}, "<C-k>", function() 
    if ls.expand_or_jumpable() then
        ls.expand_or_jump()
    end
end, {silent = true})
vim.keymap.set({"i", "s"}, "<C-j>", function()  
    if ls.jumpable(-1) then
        ls.jump(-1)
    end
end, {silent = true})
vim.keymap.set({"i", "s"}, "<C-J>", function() 
    if ls.choice_active() then
        ls.change_choice(1)
    end
end, {silent = true})

