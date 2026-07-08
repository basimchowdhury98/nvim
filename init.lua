vim.loader.enable()

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("initlazy")
require("keymaps")
require("set")
require("commands")
require("autocommands")
require("utils.terminal")

local function enable_all_configured_lsps()
    local lsp_config_path = vim.fn.stdpath("config") .. '/lsp'
    for name, _ in vim.fs.dir(lsp_config_path) do
        local lsp = name:match("^(.+)%.lua$")
        if lsp then
            vim.lsp.enable(lsp)
        end
    end
end
local function local_config_hook()
    local local_config = vim.fn.stdpath("config"):gsub("nvim$", "nvim-local") .. "/init.lua"
    if vim.uv.fs_stat(local_config) then
        dofile(local_config)
    end
end

enable_all_configured_lsps()
local_config_hook()
