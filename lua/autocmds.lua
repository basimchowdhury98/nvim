vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('UserLspConfig', { clear = true }),
    callback = function(event)
        local opts = { buffer = event.buf, remap = false }
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
    end
})
