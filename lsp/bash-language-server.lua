---@type vim.lsp.Config
return {
    cmd = { 'bash-language-server', 'start' },
    settings = {
        bashIde = {
            globPattern = '*@(.sh|.inc|.bash|.command)',
            explainshellEndpoint = 'http://localhost:5069/api'
        },
    },
    filetypes = { 'bash', 'sh' },
    root_markers = { '.git' },
}
