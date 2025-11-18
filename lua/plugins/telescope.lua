return
{
    {
        'nvim-telescope/telescope-project.nvim',
        event = "VeryLazy",
        dependencies = {
            'nvim-lua/plenary.nvim',
            {
                'nvim-telescope/telescope.nvim',
                tag = '0.1.8',
            },
            'nvim-telescope/telescope-ui-select.nvim'
        },
        config = function()
            local action_layout = require("telescope.actions.layout")
            local actions = require("telescope.actions")
            local project_actions = require("telescope._extensions.project.actions")
            require('telescope').setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<esc>"] = actions.close,
                            ["<M-p>"] = action_layout.toggle_preview,
                            ["<C-y>"] = actions.select_default,
                            ["<M-\\>"] = actions.select_vertical
                        }
                    },
                    layout_config = {
                        width = 0.9,  -- 90% of screen width
                        height = 0.8, -- 80% of screen height
                    },
                    winblend = 10
                },
                extensions = {
                    ['ui-select'] = {
                        require('telescope.themes').get_cursor {
                        }
                    },
                    project = {
                        base_dirs = {
                            "C:/Users/bchowdhury/source/repos",
                            "C:/Users/basim/Projects",
                            "/Users/basimchowdhury/Projects"
                        },
                        on_project_selected = function(prompt_bufnr)
                            require("utils.terminal").preload()
                            local harpoon = require('harpoon.ui')
                            local mark = require('harpoon.mark')
                            project_actions.change_working_directory(prompt_bufnr, false)
                            if mark.valid_index(1) then
                                harpoon.nav_file(1)
                                return
                            end
                            vim.cmd('edit . ')
                        end,
                        mappings = {
                            i = {
                                ["<C-\\>"] = function(prompt_bufnr)
                                    local action_state = require("telescope.actions.state")
                                    local selection = action_state.get_selected_entry()

                                    actions.select_vertical(prompt_bufnr)
                                    vim.cmd('lcd ' .. selection.value)
                                end
                            }
                        }
                    }
                }
            })
            require('telescope').load_extension('ui-select')
            require('telescope').load_extension('project');

            local builtin = require('telescope.builtin')
            local telescope = require('telescope')
            local themes = require('telescope.themes')

            local map = vim.keymap.set
            map('n', '<leader>fa', builtin.find_files, { desc = "[F]ind [A]ll files" })
            map('n', '<leader>fs', builtin.live_grep, { desc = "[F]ind by [S]earching using using grep" })
            map('n', '<leader>fr', builtin.resume, { desc = "[F]ind [R]esume" })
            map('n', '<leader>fk', builtin.keymaps, { desc = "[F]ind [K]eymaps" })
            map('n', '<leader>fp', telescope.extensions.project.project, { desc = "[F]ind [P]roject" })
            map('n', '<leader>fh', builtin.help_tags, { desc = "[F]ind in [H]elp" })
            map('n', '<leader>fb', function()
                builtin.buffers({ previewer = false })
            end, { desc = "[F]ind [B]uffers(open)" })
            map('n', '<leader>fc', builtin.colorscheme, { desc = "[F]ind [C]olorscheme" })
            map('n', '<leader>fj', function()
                -- Setting custom style for searching within a file
                builtin.current_buffer_fuzzy_find(themes.get_dropdown {
                    previewer = false,
                    layout_config = {
                        width = 0.9,  -- 90% of screen width
                        height = 0.8, -- 80% of screen height
                    },

                })
            end, { desc = '[F]ind in [J]ust this file' })
            map('n', '<leader>fn', function()
                builtin.find_files {
                    cwd = vim.fn.stdpath 'config',
                    prompt_title = 'Find in Neovim Config'
                }
            end, { desc = '[F]ind in [N]eovim config' })
            map('n', '<leader>fl', function()
                builtin.live_grep {
                    grep_open_files = true,
                    prompt_title = 'Grep Open Files',
                }
            end, { desc = '[F]ind by [L]uck (grep in open files)' })
            map('n', '<leader>fo', function()
                builtin.lsp_document_symbols({
                    sorting_strategy = "ascending",
                    layout_config = {
                        width = 0.9,
                        height = 0.8,
                        prompt_position = "top"
                    },
                })
            end)
        end,
    }
}
