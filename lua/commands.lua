vim.api.nvim_create_user_command("NVIM", function()
    local nvim_path = vim.fn.getenv('NVIM')
    if nvim_path == vim.NIL or nvim_path == '' then
        print("Error: $NVIM environment variable not set!")
        return
    end

    if vim.fn.isdirectory(nvim_path) == 0 then
        print("Error: NVIM config path does not exist: " .. nvim_path)
        return
    end

    vim.cmd("Vexplore " .. nvim_path)
end, {})
