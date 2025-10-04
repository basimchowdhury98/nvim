return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = 'master',
        lazy = false,
        build = ":TSUpdate",
        main = 'nvim-treesitter.configs',
        opts = {
            ensure_installed = { "c", "lua", "vim", "vimdoc", "markdown", "markdown_inline", "typescript", "javascript", "tsx", "c_sharp", "angular" },

            sync_install = false,

            auto_install = true,

            highlight = {
                enable = true,

                additional_vim_regex_highlighting = false,
            },
        }
    },
    {
        'nvim-treesitter/nvim-treesitter-context',
        config = function()
            require('treesitter-context').setup({
                enable = true,
                max_lines = 3, -- How many context lines to show
                min_window_height = 0,
                line_numbers = true,
                multiline_threshold = 2, -- Maximum number of lines to show for a single context
                trim_scope = 'outer', -- Which context lines to discard if `max_lines` is exceeded
                mode = 'cursor',     -- Line used to calculate context. Choices: 'cursor', 'topline'
            })
        end
    }
}
