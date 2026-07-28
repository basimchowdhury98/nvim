vim.pack.add {
    "https://github.com/nvim-mini/mini.ai",
}

require('mini.ai').setup {
    mappings = {
        around_next = 'an',
        inside_next = 'in',
        around_last = 'ap',
        inside_last = 'ip',
    }
}
