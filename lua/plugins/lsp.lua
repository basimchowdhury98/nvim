return {
    {
        "mason-org/mason.nvim",
        config = function()
            require("mason").setup({
                registries = {
                    "github:mason-org/mason-registry",
                    "github:Crashdummyy/mason-registry",
                }
            })
        end
    },
    {
        "mason-org/mason-lspconfig.nvim",
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "lua_ls",
                    "ts_ls"
                },
                handlers = {
                    function(server_name)
                        local capabilities = require("cmp_nvm_lsp").default_capabilities()
                        require("lspconfig")[server_name].setup({
                            capabilities = capabilities
                        })
                    end
                }
            })
        end
    },
    {
        "neovim/nvim-lspconfig"
    },
    {
        "seblyng/roslyn.nvim",
        ---@module 'roslyn.config'
        ---@type RoslynNvimConfig
        opts = {
        },
    }
}
