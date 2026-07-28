-- specs/init.lua
vim.opt.rtp:append(".")

vim.pack.add({
    "https://github.com/nvim-lua/plenary.nvim",
}, {
    confirm = false,
    load = true,
})

require("plenary.busted")
