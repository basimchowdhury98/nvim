return {
    "lewis6991/gitsigns.nvim",
    config = function ()
        local gitsigns = require("gitsigns")
        gitsigns.setup({})

        vim.keymap.set("n", "]g", function ()
            gitsigns.nav_hunk('next')
        end, { desc = 'Next [g]it hunk' })
        vim.keymap.set("n", "[g", function ()
            gitsigns.nav_hunk('prev')
        end, { desc = 'Prev [g]it hunk' })
        vim.keymap.set("n", "<leader>gd", gitsigns.preview_hunk_inline, { desc = "[G]it - [D]iff inline" })
        vim.keymap.set("n", "<leader>gr", gitsigns.reset_hunk, { desc = "[G]it - [R]eset hunk" })
    end
}
