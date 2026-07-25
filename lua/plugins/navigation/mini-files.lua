return {
    'nvim-mini/mini.files',
    version = false,
    event = "VeryLazy",
    config = function()
        local minifiles = require('mini.files')
        minifiles.setup({
            mappings = {
                go_in = "",
                go_in_plus = "<CR>",
                go_out_plus = '<ESC>',
                go_out = '',
                reset = ",",
                reveal_cwd = ".",
            },
            windows = {
                preview = true,
                width_preview = 100
            }
        })

        vim.keymap.set("n", "<leader>e", function() minifiles.open(vim.api.nvim_buf_get_name(0)) end,
            { desc = "Open minifiles file exploer" })
    end
}
