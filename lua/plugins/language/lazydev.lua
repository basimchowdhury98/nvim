return{
    "folke/lazydev.nvim",
    ft = "lua",
    config = function()
        require('lazydev.lsp').supported_clients = { 'lua-language-server' }
        require('lazydev').setup({
            library = {
                -- Load library types when the `{words}` word is found
                { path = "${3rd}/luv/library",      words = { "vim%.uv" } },
                { path = "${3rd}/busted/library",   words = { "describe" } },
                { path = "${3rd}/luassert/library", words = { "describe" } },
            },
        })
    end
}
