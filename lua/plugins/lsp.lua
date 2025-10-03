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
                        ['<C-k>'] = false,
                        ['<C-s>'] = { 'show_signature', 'hide_signature' }
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
                    signature = {
                        enabled = true,
                        trigger = {
                            enabled = true,
                            show_on_trigger_character = true,
                            show_on_insert_on_trigger_character = true,
                            show_on_accept = true,
                        },
                        window = {
                            border = 'rounded',
                            max_width = 100,
                            max_height = 10
                        }
                    },
                    fuzzy = { implementation = 'lua' }
                }
            },
        },
        config = function()
            local map = vim.keymap.set

            local ls = require("luasnip")
            ls.config.set_config {
                history = true,
                updateevents = "TextChanged,TextChangedI"
            }

            map({ "i", "s" }, "<C-k>", function()
                if ls.expand_or_jumpable() then
                    ls.expand_or_jump()
                end
            end, { silent = true, desc = "[J]ump to next node" })
            map({ "i", "s" }, "<C-j>", function()
                if ls.jumpable(-1) then
                    ls.jump(-1)
                end
            end, { silent = true, desc = "[]Jump back(opposite of j=k) to next node" })
            map({ "i", "s" }, "<C-l>", function()
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

            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup('lsp-keymaps', { clear = true }),
                callback = function(event)
                    map("n", "H", vim.lsp.buf.hover, { desc = "Lsp - show hover info", buffer = event.buf })
                    map("n", "<leader>gd", vim.lsp.buf.definition,
                        { desc = "Lsp - go to definition", buffer = event.buf })
                    map("n", "<leader>gi", vim.lsp.buf.implementation,
                        { desc = "Lsp - go to definition", buffer = event.buf })
                    map("n", "<leader>gr", vim.lsp.buf.references,
                        { desc = "Lsp - list all references", buffer = event.buf })
                    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action,
                        { desc = "Lsp - code actions", buffer = event.buf })
                    map({ "n", "v" }, "<leader>cf", vim.lsp.buf.format,
                        { desc = "Lsp - format code in file", buffer = event.buf })
                    map({ "n", "v" }, "<leader>cr", vim.lsp.buf.rename,
                        { desc = "Lsp - rename symbol under cursor", buffer = event.buf })
                end
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
