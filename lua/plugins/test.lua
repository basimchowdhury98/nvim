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

            vim.keymap.set("n", "<leader>dh", function ()
                test.run.run({ strategy = "dap" })
            end, { desc = "[D]ebug current test" } )
        end
    }
}
