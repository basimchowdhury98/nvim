vim.pack.add {
    "https://github.com/nvim-mini/mini.files",
}

local minifiles = require('mini.files')
minifiles.setup {
    mappings = {
        go_in = "l",
        go_in_plus = "<CR>",
        go_out_plus = '',
        go_out = 'h',
        reset = ",",
        reveal_cwd = ".",
        close = '<ESC>',
        synchronize = "=",
    },
    windows = {
        preview = true,
        width_preview = 100
    }
}

vim.keymap.set("n", "<leader>e",
    function() minifiles.open(vim.api.nvim_buf_get_name(0)) end,
    {
        desc = "Open minifiles file exploer"
    })
