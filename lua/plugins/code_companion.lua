return {
    {
        "olimorris/codecompanion.nvim",
        config = function()
            require("codecompanion").setup({
                strategies = {
                    chat = {
                        adapter = "anthropic",
                        keymaps = {
                            close = {
                                modes = { n = "<Esc>", i = "<Esc>" },
                                opts = {},
                            }
                        }
                    },
                    inline = {
                        adapter = "anthropic",
                        keymaps = {
                            accept_change = {
                                modes = { n = "<leader>aia" },
                                description = "Accept the suggested change",
                            },
                            reject_change = {
                                modes = { n = "<leader>air" },
                                opts = { nowait = true },
                                description = "Reject the suggested change",
                            },
                        },
                    },
                    cmd = {
                        adapter = "anthropic",
                    }
                },
                adapters = {
                    http = {
                        anthropic = function()
                            return require("codecompanion.adapters").extend("anthropic", {
                                env = {
                                    api_key = "ANTHROPIC_API_KEY"
                                },
                            })
                        end,
                    },
                },
            })

            vim.keymap.set("n", "<leader>aic", ":CodeCompanionChat<CR>", { desc = "Open CodeCompanion AI chat" })
            vim.cmd([[cab cc CodeCompanion]])
            require("plugins.code_companion.fidget_spinner"):init()
        end
    }
}
