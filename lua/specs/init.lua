-- specs/init.lua
local plenary_dir = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"

if vim.fn.isdirectory(plenary_dir) == 0 then
  error("plenary.nvim not found at " .. plenary_dir)
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")

require("plenary.busted")
