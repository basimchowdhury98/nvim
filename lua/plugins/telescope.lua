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
            require('telescope').setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<esc>"] = actions.close,
                            ["<M-p>"] = action_layout.toggle_preview,
                            ["<C-y>"] = actions.select_default
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
                        require('telescope.themes').get_dropdown {
                        }
                    },
                }
            })
            require('telescope').load_extension('ui-select')
            require('telescope').load_extension('project');

            local builtin = require('telescope.builtin')
            local telescope = require('telescope')

            local map = vim.keymap.set
            map('n', '<leader>ff', builtin.find_files, { desc = "[F]ind all [F]iles" })
            map('n', '<leader>fg', builtin.git_files, { desc = "[F]ind [G]it files" })
            map('n', '<leader>fS', builtin.live_grep, { desc = "[F]ind by [S]earch(capital) using grep" })
            map('n', '<leader>fr', builtin.resume, { desc = "[F]ind [R]esume" })
            map('n', '<leader>fk', builtin.keymaps, { desc = "[F]ind [K]eymaps" })
            map('n', '<leader>fp', telescope.extensions.project.project, { desc = "[F]ind [P]roject" })
            map('n', '<leader>fh', builtin.help_tags, { desc = "[F]ind in [H]elp" })
            map('n', '<leader>fo', builtin.buffers, { desc = "[F]ind [O]pen buffers" })
            map('n', '<leader>fc', builtin.colorscheme, { desc = "[F]ind [C]olorscheme" })
            vim.keymap.set('n', '<leader>fj', function()
                -- Setting custom style for searching within a file
                builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
                    previewer = false,
                })
            end, { desc = '[F]ind in [J]ust this file' })
            vim.keymap.set('n', '<leader>fn', function()
                builtin.find_files {
                    cwd = vim.fn.stdpath 'config',
                    prompt_title = 'Find in Neovim Config'
                }
            end, { desc = '[F]ind in [N]eovim config' })
            vim.keymap.set('n', '<leader>fs', function()
                builtin.live_grep {
                    grep_open_files = true,
                    prompt_title = 'Grep Open Files',
                }
            end, { desc = '[F]ind by [S]earching open files' })
        end,
    }
}
