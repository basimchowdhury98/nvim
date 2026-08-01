vim.pack.add {
    {
        src = 'https://github.com/saghen/blink.cmp',
        version = vim.version.range('1.*')
    }
}

local blink = require("blink.cmp")
blink.setup {
    keymap = {
        preset = "default",
        ["<C-k>"] = false,
        ["<C-s>"] = { "show_signature", "hide_signature" },
    },
    appearance = {
        nerd_font_variant = "mono",
    },
    sources = {
        default = {  "lsp", "snippets", "path", "buffer" },
        providers = {
            lsp = { async = false, timeout_ms = 2000, fallbacks = {} },
            path = { fallbacks = {} },
            buffer = { score_offset = -100 },
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
}

vim.lsp.config("*", {
    capabilities = blink.get_lsp_capabilities(),
})
