return {
    {
        'nvim-mini/mini.files',
        version = false,
        config = function ()
            local minifiles = require('mini.files')
            minifiles.setup({
                mappings = {
                    close = "<Esc>",
                    reset = ",",
                    reveal_cwd = ".",
                    go_in_plus = "<CR>"
                },
                windows = {
                    preview = true,
                    width_preview = 100
                }
            })

           vim.keymap.set("n", "<leader>e", function() minifiles.open(vim.api.nvim_buf_get_name(0)) end, { desc = "Open minifiles file exploer" })
        end
    },
}
