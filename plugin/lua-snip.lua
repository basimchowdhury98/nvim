vim.pack.add {
    "https://github.com/L3MON4D3/LuaSnip",
    "https://github.com/rafamadriz/friendly-snippets",
}

local map = vim.keymap.set

local ls = require("luasnip")
ls.config.set_config({
    history = true,
    updateevents = "InsertLeave",
})

map({ "i", "s" }, "<C-k>", function()
    if ls.expand_or_jumpable() then
        ls.expand_or_jump()
    end
end, { silent = true, desc = "Snips - [] Jump to next node" })
map({ "i", "s" }, "<C-j>", function()
    if ls.jumpable(-1) then
        ls.jump(-1)
    end
end, { silent = true, desc = "Snips - [] Jump back to previous node" })
map({ "i", "s" }, "<C-l>", function()
    if ls.choice_active() then
        ls.change_choice(1)
    end
end, { silent = true, desc = "[L]ist next choice" })

require("luasnip.loaders.from_vscode").lazy_load()
require("luasnip.loaders.from_lua").lazy_load({ paths = { "./snippet" } })

vim.api.nvim_create_user_command('SNIP', function()
    local nvim_path = vim.fn.stdpath('config')
    if nvim_path == vim.NIL or nvim_path == '' then
        print('Error: couldnt get config path')
        return
    end

    local ft = vim.bo.filetype
    local snippet_file = vim.fs.joinpath(nvim_path, 'snippet', ft .. '.lua')
    if vim.fn.filereadable(snippet_file) == 0 then
        print('Error: NVIM snippet file does not exist: ' .. snippet_file)
        return
    end


    vim.cmd('vsplit')
    vim.cmd('lcd ' .. nvim_path)
    vim.cmd('edit ' .. snippet_file)
end, {})
