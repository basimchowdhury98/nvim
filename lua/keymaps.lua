local function close_any_floats()
    for _, win in pairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' then -- floating window
            vim.api.nvim_win_close(win, false)
        end
    end
end

local show_keymap_migration
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

-- LSP
local telescope = require("telescope.builtin")
map("n", "grd", "<C-]>", { desc = "Go to definition", remap = true })
map("n", "gri", telescope.lsp_implementations, { desc = "Open implementations in telescope" })
map("n", "grr", telescope.lsp_references, { desc = "Open references in telescope" })
map("n", "grq", vim.lsp.buf.format, { desc = "Format the buffer" })

-- Temporary reminders while transitioning to Neovim's default LSP keymaps.
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-keymap-migration", { clear = true }),
    callback = function(event)
        for _, old_key in ipairs({ "H", "<leader>gi" }) do
            local key = old_key
            map("n", key, function() show_keymap_migration(key) end, {
                buffer = event.buf,
                desc = "Show replacement for " .. key,
            })
        end

        for _, old_key in ipairs({ "<leader>ca", "<leader>cf", "<leader>cr" }) do
            local key = old_key
            map({ "n", "x" }, key, function() show_keymap_migration(key) end, {
                buffer = event.buf,
                desc = "Show replacement for " .. key,
            })
        end
    end,
})

map({ "n", "x" }, "<leader>cc", function() show_keymap_migration("<leader>cc") end, {
    desc = "Show replacement for <leader>cc",
})

map("i", "<C-c>", function()
    local choice = vim.fn.confirm('<C-c> doesnt fire InsertLeave(so doesnt reload diags). Esc does. Continue?',
        "&Yes\n&No")

    if choice == 1 then
        local key = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
        vim.api.nvim_feedkeys(key, 'n', false)
    end
end, { desc = "Warn against using this bc it wont show diag so i can retrain muscle memory" })

local migration_win
local migration_namespace = vim.api.nvim_create_namespace("keymap-migration")
local migration_lines = {
    { "H",          "H           -> K           LSP hover" },
    { "<leader>gd", "<leader>gd -> grd         Go to definition" },
    { "<leader>gi", "<leader>gi -> gri         Implementations (Telescope)" },
    { "<leader>gr", "<leader>gr -> grr         References (Telescope)" },
    { "<leader>ca", "<leader>ca -> gra         Code actions" },
    { "<leader>cf", "<leader>cf -> gq{motion}  Format (whole file: gggqG)" },
    { "<leader>cr", "<leader>cr -> grn         Rename symbol" },
    { "<leader>cc", "<leader>cc -> gcc / gc    Comment line / selection" },
}

show_keymap_migration = function(selected)
    if migration_win and vim.api.nvim_win_is_valid(migration_win) then
        vim.api.nvim_win_close(migration_win, true)
    end

    local lines = {}
    local selected_line
    local width = 0

    for _, migration in ipairs(migration_lines) do
        table.insert(lines, migration[2])
        width = math.max(width, vim.fn.strdisplaywidth(migration[2]))
        if migration[1] == selected then
            selected_line = #lines
        end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    migration_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - #lines) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = #lines,
        style = "minimal",
        border = "rounded",
        title = " Keymap migration ",
        title_pos = "center",
        focusable = true,
        zindex = 60,
    })

    if selected_line then
        vim.api.nvim_buf_add_highlight(buf, migration_namespace, "Visual", selected_line - 1, 0, -1)
        vim.api.nvim_win_set_cursor(migration_win, { selected_line, 0 })
    end

    map("n", "q", function()
        if migration_win and vim.api.nvim_win_is_valid(migration_win) then
            vim.api.nvim_win_close(migration_win, true)
        end
        migration_win = nil
    end, { buffer = buf, desc = "Close keymap migration" })
end
