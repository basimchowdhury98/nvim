return {
    "lewis6991/gitsigns.nvim",
    config = function ()
        local gitsigns = require("gitsigns")
        gitsigns.setup({
        })

        vim.keymap.set("n", "]g", function ()
            gitsigns.nav_hunk('next')
        end)
        vim.keymap.set("n", "[g", function ()
            gitsigns.nav_hunk('prev')
        end)
        vim.keymap.set("n", "<leader>vd", gitsigns.preview_hunk_inline, { desc = "[V]ersion Control(gitsigns) - [D]iff inline" })
        vim.keymap.set("n", "<leader>vr", gitsigns.reset_hunk, { desc = "[V]ersion Control(gitsigns) - [R]eset hunk" })
    end
}
