vim.loader.enable()
local utils= require('utils')

require("set")
require("keymaps")
require("commands")
require("autocommands")

utils.local_config_hook()

-- init -> /plugins/* -> this command
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    nested = true,
    callback = function()
        vim.cmd.colorscheme("gruvbox-material")
        utils.enable_all_configured_lsps()
    end,
})
