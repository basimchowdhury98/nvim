return {
    {
        'saghen/blink.cmp',
        event='VimEnter',
        dependencies = {
            {
                "L3MON4D3/LuaSnip",
                dependencies = {
                    "rafamadriz/friendly-snippets",
                    config = function()
                        require("luasnip.loaders.from_vscode").lazy_load()
                    end
                }, -- Pre-made snippets
                opts = {}
            },
            'folke/lazydev.nvim'
        },
        opts = {
            keymap = {
                preset = 'default'
            },
            appearance = {
                nerd_font_variant = 'mono'
            },
            sources = {
                default = { 'lsp', 'path', 'snippets', 'lazydev' },
                providers = {
                    lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 }
                }
            },
            snippets = { preset = 'luasnip' },
            signature = { enabled = true },
            fuzzy = { implementation = 'lua' }
        }
    }
}
