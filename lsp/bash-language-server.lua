---@type vim.lsp.Config
return {
    icon = '\u{f1183}',
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
