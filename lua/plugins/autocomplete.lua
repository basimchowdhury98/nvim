return {
    {
        "hrsh7th/nvim-cmp",
        config = function()
            local cmp = require("cmp")
            cmp.setup({
                snippet = {
                    expand = function(args)
                        require("luasnip").lsp_expand(args.body)
                    end
                },
                window = {
                    completion = cmp.config.window.bordered(),
                    documentation = cmp.config.window.bordered()
                },
                sources = cmp.config.sources({
                    { name = 'nvim_lsp' },
                    { name = 'nvim_lua' },
                    { name = 'luasnip' },
                    { name = 'nvim_lsp_signature_help' }
                }, {
                    { name = 'buffer' },
                })
            })
        end
    },
    {
        "hrsh7th/cmp-buffer"
    },
    {
        "hrsh7th/cmp-path"
    },
    {
        "hrsh7th/cmp-nvim-lua"
    },
    {
        "hrsh7th/cmp-nvim-lsp"
    },
    {
        "L3MON4D3/LuaSnip"
    },
    {
        "saadparwaiz1/cmp_luasnip"
    },
    {
        "hrsh7th/cmp-nvim-lsp-signature-help"
    }
}
