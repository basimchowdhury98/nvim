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
        default = { "lsp", "snippets", "path", "buffer" },
        providers = {
            lsp = { async = false, timeout_ms = 2000, fallbacks = {} },
            path = { fallbacks = {} },
            buffer = { score_offset = -100 },
            snippets = { name = "Luasnip" }
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
    completion = {
        menu = {
            border = "rounded",
            draw = {
                columns = {
                    { "kind_icon" },
                    { "label", "label_description", gap = 1 },
                    { "source_name" },
                },
            },
        },
        documentation = {
            window = {
                border = "rounded",
            },
        },
    },
}

vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("blink-float-highlights", { clear = true }),
    callback = function()
        vim.api.nvim_set_hl(0, "BlinkCmpMenu", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpSource", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpLabelDescription", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
        vim.api.nvim_set_hl(0, "BlinkCmpDoc", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "FloatBorder" })
        vim.api.nvim_set_hl(0, "BlinkCmpDocSeparator", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelp", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })
    end,
})

vim.lsp.config("*", {
    capabilities = blink.get_lsp_capabilities(),
})
