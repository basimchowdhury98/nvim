return {
    "ThePrimeagen/harpoon",
    config = function()
        require('harpoon').setup({
            menu = {
                width = 120
            }
        })
        -- Monkey patching/wrapping original add file method to flash the text i harpooned
        local mark = require('harpoon.mark')
        local original_add_file = mark.add_file
        mark.add_file = function(...)
            local ns_id = vim.api.nvim_create_namespace("flash_file")
            local ret = original_add_file(...)
            vim.hl.range(0, ns_id, 'Visual', 'w0', 'w$', { inclusive = true, timeout = 100 })
            return ret
        end

        local map = vim.keymap.set
        local ui = require("harpoon.ui")
        map("n", "<leader>ha", mark.add_file, { desc = "Add file to harpoon" })
        map("n", "<leader>ht", ui.toggle_quick_menu, { desc = "Toggle harpoon menu" })
        map("n", "<M-1>", function() ui.nav_file(1) end, { desc = "Navigate to file 1" })
        map("n", "<M-2>", function() ui.nav_file(2) end, { desc = "Navigate to file 2" })
        map("n", "<M-3>", function() ui.nav_file(3) end, { desc = "Navigate to file 3" })
        map("n", "<M-0>", function() ui.nav_file(4) end, { desc = "Navigate to file 4" })
    end
}
