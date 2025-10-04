vim.cmd.colorscheme("gruvbox-material")
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.wrap = false
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.scrolloff = 8
vim.opt.updatetime = 50
vim.opt.colorcolumn = "120"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.nu = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.confirm = true
vim.diagnostic.config({
    virtual_lines = {
        current_line = true
    },
    underline = true,
    severity_sort = true,
    float = {
        border = "rounded",
        source = true,
        scope = "buffer"
    }
})
