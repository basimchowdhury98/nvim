vim.api.nvim_create_user_command('Mason', function()
    -- so that mason can reregister the mason command to open mason
    vim.api.nvim_del_user_command('Mason')

    vim.pack.add { "https://github.com/mason-org/mason.nvim" }
    require('mason').setup {}

    vim.cmd('Mason')
end, {})
