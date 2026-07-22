return {
    "L3MON4D3/LuaSnip",
    dependencies = {
        "rafamadriz/friendly-snippets",     --premade snippets
    },
    lazy = false,
    config = function()
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
        require("luasnip.loaders.from_lua").lazy_load({ paths = { "./snippets" } })
    end,
}
