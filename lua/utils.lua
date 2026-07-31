return {
    enable_all_configured_lsps = function(root)
        local lsp_root = root or vim.fn.stdpath("config")
        local lsp_config_path = lsp_root .. '/lsp'
        local configured_lsps = {}
        for name, _ in vim.fs.dir(lsp_config_path) do
            local lsp = name:match("^(.+)%.lua$")
            if lsp then
                table.insert(configured_lsps, lsp)
            end
        end
        vim.lsp.enable(configured_lsps)
    end,
    local_config_hook = function()
        local local_config = vim.fn.stdpath("config"):gsub("nvim$", "nvim-local") .. "/init.lua"
        if vim.uv.fs_stat(local_config) then
            dofile(local_config)
        end
    end,
    set_float_highlights = function()
        vim.api.nvim_set_hl(0, 'NormalFloat', { link = 'TelescopeNormal' })
        vim.api.nvim_set_hl(0, 'FloatBorder', { link = 'TelescopeBorder' })
        vim.api.nvim_set_hl(0, 'FloatTitle', { link = 'TelescopeTitle' })
    end
}
