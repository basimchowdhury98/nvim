vim.api.nvim_create_user_command('NVIM', function()
    local nvim_path = vim.fn.stdpath('config')
    if nvim_path == vim.NIL or nvim_path == '' then
        print('Error: couldnt get config path')
        return
    end

    if vim.fn.isdirectory(nvim_path) == 0 then
        print('Error: NVIM config path does not exist: ' .. nvim_path)
        return
    end

    vim.cmd('vsplit')
    vim.cmd('lcd ' .. nvim_path)
    vim.cmd('edit ./wishlist.txt')
end, {})

vim.api.nvim_create_user_command('W', 'w', { desc = 'W equals w because my fingers are fat' })

vim.api.nvim_create_user_command('LspLogs', function()
    local start_win = vim.api.nvim_get_current_win()
    local lsp_log_path = vim.lsp.log.get_filename()

    vim.cmd.vnew()
    vim.fn.jobstart({
        vim.o.shell,
        vim.o.shellcmdflag,
        "tail -f " .. lsp_log_path,
    }, {
        term = true,
    })

    vim.api.nvim_set_current_win(start_win)
end, { desc = "Attach lsp logs to a terminal buffer" })

vim.api.nvim_create_user_command('Pack', function ()
    vim.pack.update(nil, { offline = true })
end, { desc = 'Show current packs' })
