return
{
    {
        'nvim-telescope/telescope-project.nvim',
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
                            ["<M-p>"] = action_layout.toggle_preview
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
        end,
    }
}
