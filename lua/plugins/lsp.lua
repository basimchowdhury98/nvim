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
                        preset = 'default',
                        ['<C-k>'] = false
                    },
                    appearance = {
                        nerd_font_variant = 'mono'
                    },
                    sources = {
                        default = { 'lsp', 'path', 'snippets', 'lazydev', 'buffer' },
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
            local ls = require("luasnip")
            ls.config.set_config {
                history = true,
                updateevents = "TextChanged,TextChangedI"
            }

            vim.keymap.set({ "i", "s" }, "<C-k>", function()
                if ls.expand_or_jumpable() then
                    ls.expand_or_jump()
                end
            end, { silent = true, desc = "[J]ump to next node" })
            vim.keymap.set({ "i", "s" }, "<C-j>", function()
                if ls.jumpable(-1) then
                    ls.jump(-1)
                end
            end, { silent = true, desc = "[]Jump back(opposite of j=k) to next node" })
            vim.keymap.set({ "i", "s" }, "<C-l>", function()
                if ls.choice_active() then
                    ls.change_choice(1)
                end
            end, { silent = true, desc = "[L]ist next choice" })

            require("luasnip.loaders.from_vscode").lazy_load()
            require("luasnip.loaders.from_lua").lazy_load({ paths = { "./lua/snippets" } })


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
