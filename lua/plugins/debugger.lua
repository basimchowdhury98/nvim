return {
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "theHamsta/nvim-dap-virtual-text",
            "nvim-neotest/nvim-nio",
            "ramboe/ramboe-dotnet-utils"
        },
        config = function()
            local mason_path = vim.fn.stdpath("data") .. "/mason/packages/netcoredbg/netcoredbg/netcoredbg"
            local dap = require("dap")
            local dap_utils = require("dap.utils")
            local dapui = require("dapui")
            dapui.setup()
            require("nvim-dap-virtual-text").setup({})

            local adapter = {
                type = "executable",
                command = mason_path,
                args = { "--interpreter=vscode" }
            }
            dap.adapters.coreclr = adapter
            dap.adapters.netcoredbg = adapter

            dap.configurations.cs = {
                {
                    type = "coreclr",
                    name = "LAUNCH directly from nvim",
                    request = "launch",
                    program = function()
                        return require("dap-dll-autopicker").build_dll_path()
                    end
                },
                {
                    type = "coreclr",
                    name = "Attach",
                    request = "attach",
                    processId = dap_utils.pick_process,
                },
            }

            vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "[D]ebug [B]reakpoint" })
            vim.keymap.set("n", "<leader>d<leader>", dap.continue, { desc = "[D]ebug start/continue" })
            vim.keymap.set("n", "<leader>dj", dap.terminate, { desc = "[D]ebug terminate(j for down/shutdown)" })
            vim.keymap.set("n", "<leader>dk", dap.restart, { desc = "[D]ebug restart(k for up/go back up/restart" })
            vim.keymap.set("n", "<leader>dl", dap.run_to_cursor, { desc = "[D]ebug run to cursor(l for next)" })
            vim.keymap.set("n", "<leader>d/", function()
                dapui.eval(nil, { enter = true })
            end, { desc = "[D]ebug inspect(implicitly ?)" })

            local original_mappings = {}

            local uiOpen = function()
                dapui.open()
                -- Save original mappings (if they exist)
                original_mappings['<C-j>'] = vim.fn.maparg('<C-j>', 'n', false, true)
                original_mappings['<C-k>'] = vim.fn.maparg('<C-k>', 'n', false, true)
                original_mappings['<C-l>'] = vim.fn.maparg('<C-l>', 'n', false, true)

                vim.keymap.set('n', '<C-j>', dap.step_over, { desc = 'Debug: Step Over' })
                vim.keymap.set('n', '<C-l>', dap.step_into, { desc = 'Debug: Step Into' })
                vim.keymap.set('n', '<C-k>', dap.step_out, { desc = 'Debug: Step Out' })
            end

            local uiClose = function()
                dapui.close()
                vim.keymap.del('n', '<C-j>')
                vim.keymap.del('n', '<C-k>')
                vim.keymap.del('n', '<C-l>')

                for key, mapping in pairs(original_mappings) do
                    if mapping and mapping.rhs then
                        vim.keymap.set('n', key, mapping.rhs, { silent = mapping.silent == 1 })
                    end
                end
            end

            dap.listeners.before.attach.dapui_config = function()
                uiOpen()
            end
            dap.listeners.before.launch.dapui_config = function()
                uiOpen()
            end
            dap.listeners.before.event_terminated.dapui_config = function()
                uiClose()
            end
            dap.listeners.before.event_exited.dapui_config = function()
                uiClose()
            end
        end
    }
}
