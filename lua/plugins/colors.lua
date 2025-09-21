return {
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        opts = {
            transparent = true
        },
    },
    {
        'sainnhe/gruvbox-material',
        lazy = false,
        priority = 1000,
        config = function()
            vim.g.gruvbox_material_enable_italic = true
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
