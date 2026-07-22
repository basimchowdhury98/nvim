vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
        vim.highlight.on_yank()
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    callback = function()
        vim.cmd("wincmd L")
    end,
})

-- Automatically resize split when window is resized
vim.api.nvim_create_autocmd('VimResized', {
    pattern = '*',
    command = 'wincmd ='
})

-- In c# changes all !bool to not bool so its more visible
vim.api.nvim_create_autocmd("FileType", {
    pattern = "cs",
    callback = function()
        local ns = vim.api.nvim_create_namespace('not_operator')

        local function update_conceals()
            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

            local ok, parser = pcall(vim.treesitter.get_parser, 0, 'c_sharp')
            if not ok or not parser then return end

            local tree = parser:parse()[1]
            if not tree then return end
            local root = tree:root()

            local query = vim.treesitter.query.parse('c_sharp', [[
                (prefix_unary_expression) @negation
            ]])

            for _, node in query:iter_captures(root, 0) do
                local row, col, _, _ = node:range()
                local text = vim.treesitter.get_node_text(node, 0)

                if text:match('^!') then
                    -- Use a single extmark: conceal the '!' and place 'not ' as inline virtual text
                    vim.api.nvim_buf_set_extmark(0, ns, row, col, {
                        end_col = col + 1,
                        conceal = '',
                        virt_text = { { 'not ', 'Operator' } },
                        virt_text_pos = 'inline',
                    })
                end
            end
        end

        -- Set conceallevel so the conceal extmark actually hides the '!'
        vim.opt_local.conceallevel = 2
        vim.opt_local.concealcursor = ''

        update_conceals()
        vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
            buffer = 0,
            callback = update_conceals,
        })
    end,
})

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-presentation", { clear = true }),
    callback = function(event)
        local client = vim.lsp.get_client_by_id(event.data.client_id)

        if
            client
            and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf)
        then
            local highlight_augroup = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })

            -- When cursor stops moving: Highlights all instances of the symbol under the cursor
            -- When cursor moves: Clears the highlighting
            vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                buffer = event.buf,
                group = highlight_augroup,
                callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                buffer = event.buf,
                group = highlight_augroup,
                callback = vim.lsp.buf.clear_references,
            })

            -- When LSP detaches: Clears the highlighting
            vim.api.nvim_create_autocmd("LspDetach", {
                group = vim.api.nvim_create_augroup("lsp-detach", { clear = true }),
                callback = function(event2)
                    vim.lsp.buf.clear_references()
                    vim.api.nvim_clear_autocmds({ group = "lsp-highlight", buffer = event2.buf })
                end,
            })
        end
    end,
})

vim.api.nvim_create_autocmd('CmdlineEnter', {
    group = vim.api.nvim_create_augroup("cmd-height-1", { clear = true }),
    callback = function()
        vim.o.cmdheight = 1
    end
})
vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = vim.api.nvim_create_augroup("cmd-height-0", { clear = true }),
    callback = function()
        vim.o.cmdheight = 0
    end
})
