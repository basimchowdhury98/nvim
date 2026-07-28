vim.pack.add {
    "https://github.com/sainnhe/gruvbox-material",
}

vim.g.gruvbox_material_transparent_background = 1
vim.g.gruvbox_material_enable_italic = true
vim.g.gruvbox_material_foreground = 'mix'
vim.g.gruvbox_material_background = 'hard'
vim.g.gruvbox_material_ui_contrast = 'high'
vim.g.gruvbox_material_float_style = 'bright'
vim.g.gruvbox_material_statusline_style = 'material'
vim.g.gruvbox_material_cursor = 'auto'

vim.cmd.colorscheme('gruvbox-material')

local transparent = true
vim.api.nvim_create_user_command('FLASH', function()
    if vim.g.colors_name ~= 'gruvbox-material' then
        vim.notify('ToggleTransparency only works with gruvbox-material colorscheme', vim.log.levels.ERROR)
        return
    end

    transparent = not transparent
    vim.g.gruvbox_material_transparent_background = transparent and 1 or 0
    vim.cmd('colorscheme gruvbox-material')
end, { desc = 'Toggle transparency' })
