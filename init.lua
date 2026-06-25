vim.loader.enable()

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("initlazy")
require("keymaps")
require("set")
require("commands")
require("autocommands")
require("utils.terminal")

-- Load machine-local config if it exists
local local_config = vim.fn.stdpath("config"):gsub("nvim$", "nvim-local") .. "/init.lua"
if vim.uv.fs_stat(local_config) then
  dofile(local_config)
end
