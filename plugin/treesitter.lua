vim.pack.add {
    {
        src = "https://github.com/nvim-treesitter/nvim-treesitter",
        version = 'main'
    },
    "https://github.com/nvim-treesitter/nvim-treesitter-context",
}

require('treesitter-context').setup {
    enable = true,
    max_lines = 3, -- How many context lines to show
    min_window_height = 0,
    line_numbers = true,
    multiline_threshold = 2, -- Maximum number of lines to show for a single context
    trim_scope = "outer",    -- Which context lines to discard if `max_lines` is exceeded
    mode = "cursor",         -- Line used to calculate context. Choices: 'cursor', 'topline'
}

local function enable_treesitter_with_indent(buf, lang)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    pcall(vim.treesitter.start, buf, lang)

    if vim.treesitter.query.get(lang, "indents") then
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
end

vim.api.nvim_create_autocmd("FileType", {
    callback = function(event)
        local ts = require('nvim-treesitter')
        local lang = vim.treesitter.language.get_lang(event.match) or event.match
        local already_installed = ts.get_installed()
        if vim.tbl_contains(already_installed, lang) then
            enable_treesitter_with_indent(event.buf, lang)
            return
        end

        local available = ts.get_available()
        if not vim.tbl_contains(available, lang) then
            return
        end

        ts.install(lang):await(function(err, success)
            vim.schedule(function()
                if err or not success then
                    vim.notify(
                        ("Failed to install Treesitter parser %s: %s"):format(lang, err),
                        vim.log.levels.ERROR
                    )
                    return
                end
                enable_treesitter_with_indent(event.buf, lang)
            end)
        end)
    end,
})

vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
        local name, kind = ev.data.spec.name, ev.data.kind
        if name == 'nvim-treesitter' and kind == 'update' then
            if not ev.data.active then vim.cmd.packadd('nvim-treesitter') end
            vim.cmd('TSUpdate')
        end
    end
})
