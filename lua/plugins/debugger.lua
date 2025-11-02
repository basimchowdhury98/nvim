return {
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "theHamsta/nvim-dap-virtual-text",
            "nvim-neotest/nvim-nio",
        },
        config = function()
            local mason_path = vim.fn.stdpath("data") .. "/mason/packages/netcoredbg/netcoredbg/netcoredbg"
            local dap = require("dap")
            local dap_utils = require("dap.utils")
            local dapui = require("dapui")
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

            -- UI
            vim.fn.sign_define('DapBreakpoint',
                {
                    text = '⚪',
                    texthl = 'DapBreakpointSymbol',
                    linehl = 'DapBreakpoint',
                    numhl = 'DapBreakpoint'
                })

            vim.fn.sign_define('DapStopped',
                {
                    text = '🔴',
                    texthl = 'yellow',
                    linehl = 'DapBreakpoint',
                    numhl = 'DapBreakpoint'
                })
            vim.fn.sign_define('DapBreakpointRejected',
                {
                    text = '⭕',
                    texthl = 'DapStoppedSymbol',
                    linehl = 'DapBreakpoint',
                    numhl = 'DapBreakpoint'
                })

            -- more minimal ui
            dapui.setup({
                expand_lines = true,
                controls = { enabled = false }, -- no extra play/step buttons
                floating = { border = "rounded" },

                -- Set dapui window
                render = {
                    max_type_length = 60,
                    max_value_lines = 200,
                },

                -- Only one layout: just the "scopes" (variables) list at the bottom
                layouts = {
                    {
                        elements = {
                            { id = "scopes", size = 1.0 }, -- 100% of this panel is scopes
                        },
                        size = 15,     -- height in lines (adjust to taste)
                        position = "bottom", -- "left", "right", "top", "bottom"
                    },
                },
            })
        end
    }
}
