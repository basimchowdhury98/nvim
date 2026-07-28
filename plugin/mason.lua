vim.pack.add({ "https://github.com/mason-org/mason.nvim" }, {
    load = function(plug)
        vim.api.nvim_create_user_command('Mason', function()
            -- so that mason can reregister the mason command to open mason
            vim.api.nvim_del_user_command('Mason')
            vim.cmd.packadd(plug.spec.name)
            require('mason').setup {}

            vim.cmd('Mason')
        end, {})
    end
})
