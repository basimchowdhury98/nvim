return
{
    {
        'nvim-telescope/telescope.nvim',
        tag = '0.1.8',
        dependencies = { 'nvim-lua/plenary.nvim' },
    },
    {
        'nvim-telescope/telescope-ui-select.nvim',
    },
    {
        'nvim-telescope/telescope-project.nvim',
        config = function()
            require('telescope').setup({
                defaults = {
                    layout_config = {
                        width = 0.9,  -- 90% of screen width
                        height = 0.8, -- 80% of screen height
                    },
                },
                extensions = {
                    ['ui-select'] = {
                        require('telescope.themes').get_dropdown {
                        }
                    },
                    file_browser = {
                        hijack_netrw = true
                    }
                }
            })
            require('telescope').load_extension('ui-select')
            require('telescope').load_extension('project');
        end,
    }
}
