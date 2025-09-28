return {
    "ThePrimeagen/harpoon",
    config = function()
        require('harpoon').setup({
            menu = {
                width = vim.api.nvim_win_get_width(0) - 4
            }
        })
        -- Monkey patching/wrapping original add file method to print the file thats being added
        local mark = require('harpoon.mark')
        local original_add_file = mark.add_file
        mark.add_file = function(...)
            local ns_id = vim.api.nvim_create_namespace("flash_file")
            local ret = original_add_file(...)
            vim.hl.range(0, ns_id, 'Visual', 'w0', 'w$', { inclusive = true, timeout = 100 })
            print("Harpooned: " .. vim.fn.expand("%"))
            return ret
        end
    end
}
