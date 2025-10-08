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

    vim.cmd("Vexplore " .. nvim_path)
    vim.cmd("lcd %:p:h")
end, {})

vim.api.nvim_create_user_command('W', 'w', { desc = "W equals w because my fingers are fat" })
