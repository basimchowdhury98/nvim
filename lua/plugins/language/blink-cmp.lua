return {
    "saghen/blink.cmp",
    event = "VimEnter",
    dependencies = {
        "saghen/blink.lib",
        "L3MON4D3/LuaSnip",
    },
    opts = {
        keymap = {
            preset = "default",
            ["<C-k>"] = false,
            ["<C-s>"] = { "show_signature", "hide_signature" },
        },
        appearance = {
            nerd_font_variant = "mono",
        },
        sources = {
            default = { "lsp", "lazydev", "path", "snippets", "buffer" },
            providers = {
                lazydev = { module = "lazydev.integrations.blink", score_offset = 100 },
                lsp = { async = true, fallbacks = {} },
            },
        },
        snippets = { preset = "luasnip" },
        signature = {
            enabled = true,
            trigger = {
                enabled = true,
                show_on_trigger_character = true,
                show_on_insert_on_trigger_character = true,
                show_on_accept = true,
            },
            window = {
                border = "rounded",
                max_width = 100,
                max_height = 10,
            },
        },
        fuzzy = { implementation = "lua" },
    },
    config = function()
        vim.lsp.config("*", {
            capabilities = require("blink.cmp").get_lsp_capabilities(),
        })
    end,
}
