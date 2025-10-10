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

            local telescope = require("telescope.builtin")
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup('lsp-keymaps', { clear = true }),
                callback = function(event)
                    map("n", "H", vim.lsp.buf.hover, { desc = "Lsp - show hover info", buffer = event.buf })
                    map("n", "<leader>gd", vim.lsp.buf.definition,
                        { desc = "Lsp - go to definition", buffer = event.buf })
                    map("n", "<leader>gi", telescope.lsp_implementations,
                        { desc = "Lsp - go to implementation", buffer = event.buf })
                    map("n", "<leader>gr", telescope.lsp_references,
                        { desc = "Lsp - list all references", buffer = event.buf })
                    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action,
                        { desc = "Lsp - code actions", buffer = event.buf })
                    map({ "n", "v" }, "<leader>cf", vim.lsp.buf.format,
                        { desc = "Lsp - format code in file", buffer = event.buf })
                    map({ "n", "v" }, "<leader>cr", vim.lsp.buf.rename,
                        { desc = "Lsp - rename symbol under cursor", buffer = event.buf })
                end
            })

            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("lsp-presentation", { clear = true }),
                callback = function(event)
                    local function client_supports_method(client, method, bufnr)
                        if vim.fn.has 'nvim-0.11' == 1 then
                            return client:supports_method(method, bufnr)
                        else
                            return client.supports_method(method, { bufnr = bufnr })
                        end
                    end

                    -- Starting semantics token so treesitter can color better
                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client.server_capabilities.semanticTokensProvider then
                        vim.lsp.semantic_tokens.start(event.buf, client.id)
                    end

                    if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
                        local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })

                        -- When cursor stops moving: Highlights all instances of the symbol under the cursor
                        -- When cursor moves: Clears the highlighting
                        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.document_highlight,
                        })
                        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.clear_references,
                        })

                        -- When LSP detaches: Clears the highlighting
                        vim.api.nvim_create_autocmd('LspDetach', {
                            group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
                            callback = function(event2)
                                vim.lsp.buf.clear_references()
                                vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = event2.buf }
                            end,
                        })
                    end
                end,
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
