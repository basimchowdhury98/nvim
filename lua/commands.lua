vim.api.nvim_create_user_command("NVIM", function()
    local nvim_path = vim.fn.stdpath('config')
    if nvim_path == vim.NIL or nvim_path == '' then
        print("Error: couldnt get config path")
        return
    end

    if vim.fn.isdirectory(nvim_path) == 0 then
        print("Error: NVIM config path does not exist: " .. nvim_path)
        return
    end

    vim.cmd("vsplit")
    vim.cmd("lcd " .. nvim_path)
    vim.cmd("edit ./wishlist.txt")
end, {})

vim.api.nvim_create_user_command('W', 'w', { desc = "W equals w because my fingers are fat" })

local transparent = true

vim.api.nvim_create_user_command("FLASH", function()
    if vim.g.colors_name ~= "gruvbox-material" then
        vim.notify("ToggleTransparency only works with gruvbox-material colorscheme", vim.log.levels.ERROR)
        return
    end

    transparent = not transparent
    vim.g.gruvbox_material_transparent_background = transparent and 1 or 0
    vim.cmd("colorscheme gruvbox-material")
end, { desc = "Toggle transparency" })
