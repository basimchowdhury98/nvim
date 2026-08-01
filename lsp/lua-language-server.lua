local root_markers = {
    '.luarc.json',
    '.git'
}

-- Use one LuaLS workspace per Neovim session.
-- The first Lua buffer determines the root. Later Lua buffers attach to
-- that client and LuaLS handles them as workspace, library, or fallback files.
local active_client_root = nil

---@type vim.lsp.Config
return {
    icon = '\u{e620}',
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    root_dir = function (bufnr, on_root)
        if active_client_root then
            on_root(active_client_root)
            return
        end

        local root = vim.fs.root(bufnr, root_markers)
        if root then
            on_root(root)
            active_client_root = root
        end
    end,
    settings = {
        Lua = {
            runtime = {
                version = 'LuaJIT'
            }
        },
    },
}
