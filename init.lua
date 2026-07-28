vim.loader.enable()

require("set")
require("keymaps")
require("commands")
require("autocommands")

local function enable_all_configured_lsps()
    local lsp_config_path = vim.fn.stdpath("config") .. '/lsp'
    local configured_lsps = {}
    for name, _ in vim.fs.dir(lsp_config_path) do
        local lsp = name:match("^(.+)%.lua$")
        if lsp then
            table.insert(configured_lsps, lsp)
        end
    end
    vim.lsp.enable(configured_lsps)
end
local function local_config_hook()
    local local_config = vim.fn.stdpath("config"):gsub("nvim$", "nvim-local") .. "/init.lua"
    if vim.uv.fs_stat(local_config) then
        dofile(local_config)
    end
end

local_config_hook()

-- init -> /plugins/* -> this command
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    nested = true,
    callback = function()
        vim.cmd.colorscheme("gruvbox-material")
        enable_all_configured_lsps()
    end,
})
