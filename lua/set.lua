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
    },
})

-- Visual
vim.cmd.colorscheme "gruvbox-material"
vim.o.relativenumber = true
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.wrap = false
vim.o.expandtab = true
vim.o.scrolloff = 8
vim.o.colorcolumn = "120"
vim.o.nu = true
vim.o.termguicolors = true
vim.o.cursorline = true
vim.o.list = true
vim.opt.listchars = {  eol = "↲", trail = "·", tab = "» ", leadmultispace = "»   " }
vim.api.nvim_set_hl(0, 'Visual', { bg = '#5a3500' }) -- Bright orange visual selection
vim.o.guicursor = "n-c-sm:block,i-ci-ve:ver25,r-cr-o-v:hor20"
vim.o.showmode = false

-- File handling
vim.o.backup = false
vim.o.writebackup = false
vim.o.swapfile = false
vim.o.updatetime = 250
vim.o.timeoutlen = 500
vim.o.ttimeoutlen = 0
vim.o.autoread = true
vim.o.autowrite = false

-- Behavior
vim.o.hlsearch = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.confirm = true
vim.opt.clipboard:append("unnamedplus")
vim.o.splitright = true
