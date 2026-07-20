local root_markers = {
    '.luarc.json',
    '.luarc.jsonc',
    '.luacheckrc',
    '.git'
}

-- using lazyvim to add to this lsp(see in plugins)
---@type vim.lsp.Config
return {
    icon = '\u{e620}',
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    root_markers = root_markers,
    settings = {
        Lua = {
            runtime = {
                version = 'LuaJIT'
            }
        },
    },
}
