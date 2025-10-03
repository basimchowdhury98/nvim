return {
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        opts = {
            transparent = true,
            on_highlights = function(hl, c)
                hl.LineNr = { fg = "#2a3158" }                -- all relative line numbers darker
                hl.CursorLineNr = { fg = "#7aa2f7", bold = true } -- current line number (keep visible)
            end
        },
    },
    {
        'sainnhe/gruvbox-material',
        lazy = false,
        priority = 1000,
        config = function()
            vim.g.gruvbox_material_transparent_background = 1
            vim.g.gruvbox_material_enable_italic = true
            vim.g.gruvbox_material_foreground = 'mix'
            vim.g.gruvbox_material_background = 'hard'
            vim.g.gruvbox_material_ui_contrast = 'high'
            vim.g.gruvbox_material_float_style = 'bright'
            vim.g.gruvbox_material_statusline_style = 'material'
            vim.g.gruvbox_material_cursor = 'auto'
        end
    },
    { 'nvim-mini/mini.icons', version = false },
    {
        "prichrd/netrw.nvim",
        opts = {},
        config = function()
            require("mini.icons").setup()
            require("netrw").setup({
                use_devicons = true,
                -- other options
            })
        end
    }
}
