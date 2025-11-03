return {
    {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "Issafalcon/neotest-dotnet",
        },
        config = function()
            local test = require('neotest')
            test.setup({
                adapters = {
                    require("neotest-dotnet")
                }
            })

            vim.keymap.set("n", "<leader>rl", test.summary.toggle, { desc = "[R]un test summary wind to right [l]" })
            vim.keymap.set("n", "<leader>dh", function ()
                test.run.run({ strategy = "dap" })
            end, { desc = "[D]ebug [H](ere)/current test" } )
            vim.keymap.set("n", "<leader>rj", function ()
                test.run.run(vim.fn.expand("%"))
            end, { desc = "[R]un test [J](for down the file)" } )
        end
    }
}
