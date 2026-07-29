vim.pack.add {
    "https://github.com/nvim-mini/mini.files",
}

local minifiles = require('mini.files')
minifiles.setup {
    mappings = {
        go_in = "l",
        go_in_plus = "<CR>",
        go_out_plus = '',
        go_out = 'h',
        reset = ",",
        reveal_cwd = ".",
        close = '<ESC>',
        synchronize = "=",
    },
    windows = {
        preview = true,
        width_preview = 100
    },
    content = {
        filter = function(entry)
            return not vim.startswith(entry.name, ".")
        end,
    },
}

vim.keymap.set("n", "<leader>e", function() minifiles.open(vim.api.nvim_buf_get_name(0)) end,
    {
        desc = "Open minifiles file exploer"
    })

-- Allow for toggling of hidden files with a * indicator
local show_hidden = false
local filter_show = function() return true end
local filter_hide = function(fs_entry)
    return not vim.startswith(fs_entry.name, '.')
end
local toggle_dotfiles = function()
    show_hidden = not show_hidden
    local new_filter = show_hidden and filter_show or filter_hide
    MiniFiles.refresh({ content = { filter = new_filter } })
end
vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniFilesBufferCreate',
    callback = function(event)
        local buf_id = event.data.buf_id
        vim.keymap.set('n', '<leader>e', toggle_dotfiles, { buffer = buf_id })
    end
})
vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniFilesWindowUpdate',
    callback = function(event)
        local config = vim.api.nvim_win_get_config(event.data.win_id)
        local title = config.title

        if type(title) ~= 'table' or #title == 0 then
            return
        end

        local last_chunk = title[#title]
        last_chunk[1] = last_chunk[1]:gsub(' %* $', ' ')
        if not show_hidden then
            last_chunk[1] = last_chunk[1]:gsub(' $', ' * ')
        end

        vim.api.nvim_win_set_config(event.data.win_id, config)
    end,
})

-- Set the visuals of the file windows to be like telescope(transparent)
local function set_minifiles_highlights()
    vim.api.nvim_set_hl(0, 'MiniFilesNormal', {
        link = 'TelescopeNormal',
    })

    vim.api.nvim_set_hl(0, 'MiniFilesBorder', {
        link = 'TelescopeBorder',
    })

    vim.api.nvim_set_hl(0, 'MiniFilesTitle', {
        link = 'TelescopeTitle',
    })

    vim.api.nvim_set_hl(0, 'MiniFilesTitleFocused', {
        link = 'TelescopeTitle',
    })
end
set_minifiles_highlights()

vim.api.nvim_create_autocmd('ColorScheme', {
    callback = set_minifiles_highlights,
})
