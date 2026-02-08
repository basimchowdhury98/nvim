-- input.lua
-- Popup input window for chat message entry

local M = {}

local default_config = {
    width = 60,
    height = 5,
    border = "rounded",
    title = " Message ",
}

local config = vim.deepcopy(default_config)

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

--- Open a popup input window near the cursor
--- @param on_submit fun(text: string) Called with the message text when user presses <CR>
--- @return number buf_id The buffer id of the input popup
function M.open(on_submit)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = "markdown"

    -- Position near the cursor
    local win_opts = {
        relative = "cursor",
        width = config.width,
        height = config.height,
        row = 1,
        col = 0,
        style = "minimal",
        border = config.border,
        title = config.title,
        title_pos = "center",
    }

    local win = vim.api.nvim_open_win(buf, true, win_opts)

    -- Style the window
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = false

    -- Start in insert mode
    vim.cmd("startinsert")

    local function submit()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = vim.fn.trim(table.concat(lines, "\n"))

        -- Close the popup
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end

        if text ~= "" then
            on_submit(text)
        end
    end

    -- Submit: <CR> in insert mode sends the message
    vim.keymap.set("i", "<CR>", function()
        vim.cmd("stopinsert")
        -- defer so the mode switch completes before we close the buffer
        vim.schedule(submit)
    end, { buffer = buf, desc = "AI: Send message" })

    -- Also allow <CR> in normal mode
    vim.keymap.set("n", "<CR>", submit, { buffer = buf, desc = "AI: Send message" })

    -- Cancel: q in normal mode closes without sending
    local function cancel()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end

    vim.keymap.set("n", "q", cancel, { buffer = buf, desc = "AI: Cancel input" })
    vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, desc = "AI: Cancel input" })
    vim.keymap.set("i", "<Esc>", function()
        vim.cmd("stopinsert")
        vim.schedule(cancel)
    end, { buffer = buf, desc = "AI: Cancel input" })

    return buf
end

return M
