return {
    "ThePrimeagen/harpoon",
    config = function()
        -- Monkey patching/wrapping original add file method to print the file thats being added
        local mark = require('harpoon.mark')
        local original_add_file = mark.add_file
        mark.add_file = function(...)
            local ret = original_add_file(...)
            print("Harpooned: " .. vim.fn.expand("%"))
            return ret
        end
    end
}
