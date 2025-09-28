return {
    {
        "neovim/nvim-lspconfig",
        event = 'VeryLazy',
        dependencies = {
            "mason-org/mason-lspconfig.nvim",
            "L3MON4D3/LuaSnip",
            "mason-org/mason.nvim",
            "rafamadriz/friendly-snippets", --premade snippets
            {
                'saghen/blink.cmp',
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
            },
        },
        config = function()
            require("luasnip.loaders.from_vscode").lazy_load()
            require("mason").setup({
                registries = {
                    "github:mason-org/mason-registry",
                    "github:Crashdummyy/mason-registry",
                }
            })
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "lua_ls",
                    "ts_ls"
                },
                handlers = {
                    function(server_name)
                        local capabilities = require('blink.cmp').get_lsp_capabilities()
                        require("lspconfig")[server_name].setup({
                            capabilities = capabilities
                        })
                    end
                }
            })
        end
    },
    {
        "seblyng/roslyn.nvim",
        ft = { "cs" },
        ---@module 'roslyn.config'
        ---@type RoslynNvimConfig
        opts = {
        },
    },
    {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
            library = {
                -- Load luvit types when the `vim.uv` word is found
                { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
            },
        }
    }
}
