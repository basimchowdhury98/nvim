local function close_any_floats()
    for _, win in pairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' then -- floating window
            vim.api.nvim_win_close(win, false)
        end
    end
end
local map = vim.keymap.set

map("v", "D", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
map("v", "U", ":m '<-2<CR>gv=gv", { desc = "Move slected line up" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "" })
map("n", "N", "Nzzzv", { desc = "" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Previous diagnostic" })
map("n", "<leader>dd", vim.diagnostic.open_float, { desc = "Opens float with all diags in buffer" })
map('n', '<leader>cc', 'gcc', { remap = true, desc = 'Comment line' })
map('v', '<leader>cc', 'gc', { remap = true, desc = 'Comment selection' })
map('v', 'J', 'j', { remap = true, desc = 'Remapped J to j to stop merging line under on accident' })
map('x', "p", "\"_dP", { desc = "Paste without copying whats pasted over" })

map('n', '<leader>kp', function()
    local path = vim.fn.expand('%:p')
    vim.fn.setreg('+', path) -- system clipboard
    vim.fn.setreg('"', path) -- default yank register
end, { desc = "Copy current buffer path" })


map({ 'n', 't' }, '<Esc><Esc>', close_any_floats, { desc = 'Close floating windows' })

map("i", "<C-l>", "<Esc>la", { desc = "Move one char left in insert mode" })
map("i", "<S-CR>", "<Esc>$o", { desc = "From anywhere in line enter into a new line in insert mode" })
map("t", "<C-p>", "<Up>", { desc = "[P]revious terminal command" })
map("t", "<C-n>", "<Down>", { desc = "[N]ext terminal command" })


-- Buffer nav
map({ "n" }, "<leader>a", "ggVG", { desc = "[A]ll select" })
map({ "n" }, "<leader>/", ":noh<CR>", { desc = "Clear hl" })


-- Quick fix
map("n", "<leader>qc", ":cclose<CR>", { desc = "Close quickfix" })

-- Splits
map("n", "<C-h>", "<C-w>h", { desc = "Nav to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Nav to down split" })
map("n", "<C-k>", "<C-w>k", { desc = "Nav to up split" })
map("n", "<C-l>", "<C-w>l", { desc = "Nav to right split" })
map("n", "<leader>\\", ":vsplit<CR>", { desc = "Open vertical split" })
map("n", "<leader>-", ":split<CR>", { desc = "Open horizontal split" })
map("n", "<C-Left>", ":vertical resize +2<CR>", { desc = "Decrease split width" })
map("n", "<C-Right>", ":vertical resize -2<CR>", { desc = "Increase split width" })
map("n", "<C-Down>", ":resize +2<CR>", { desc = "Decrease split height" })
map("n", "<C-Up>", ":resize -2<CR>", { desc = "Increase split height" })

-- Testing
map("n", "<leader>x", function()
    vim.cmd('so %')
end)

local telescope = require("telescope.builtin")
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-keymaps", { clear = true }),
    callback = function(event)
        map("n", "H", vim.lsp.buf.hover, { desc = "Lsp - show hover info", buffer = event.buf })
        map(
            "n",
            "<leader>gd",
            vim.lsp.buf.definition,
            { desc = "Lsp - go to definition", buffer = event.buf }
        )
        map(
            "n",
            "<leader>gi",
            telescope.lsp_implementations,
            { desc = "Lsp - go to implementation", buffer = event.buf }
        )
        map(
            "n",
            "<leader>gr",
            telescope.lsp_references,
            { desc = "Lsp - list all references", buffer = event.buf }
        )
        map(
            { "n", "v" },
            "<leader>ca",
            vim.lsp.buf.code_action,
            { desc = "Lsp - code actions", buffer = event.buf }
        )
        map(
            { "n", "v" },
            "<leader>cf",
            vim.lsp.buf.format,
            { desc = "Lsp - format code in file", buffer = event.buf }
        )
        map(
            { "n", "v" },
            "<leader>cr",
            vim.lsp.buf.rename,
            { desc = "Lsp - rename symbol under cursor", buffer = event.buf }
        )
    end,
})

map("i", "<C-c>", function()
    local choice = vim.fn.confirm('<C-c> doesnt fire InsertLeave(so doesnt reload diags). Esc does. Continue?',
        "&Yes\n&No")

    if choice == 1 then
        local key = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
        vim.api.nvim_feedkeys(key, 'n', false)
    end
end, { desc = "Warn against using this bc it wont show diag so i can retrain muscle memory" })
