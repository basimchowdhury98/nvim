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

-- Visual
vim.opt.cursorline = true
vim.opt.list = true
vim.opt.listchars = { leadmultispace = "│   ", trail = "-" }
vim.api.nvim_set_hl(0, 'Visual', { bg = '#5a3500' })  -- Bright orange visaul selection

-- File handling
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.updatetime = 250
vim.opt.timeoutlen = 500
vim.opt.ttimeoutlen = 0
vim.opt.autoread = true
vim.opt.autowrite = false

-- Behavior
vim.opt.clipboard:append("unnamedplus")
vim.opt.splitright = true
