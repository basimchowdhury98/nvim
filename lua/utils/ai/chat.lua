-- chat.lua
-- Chat buffer management: right-side split, read-only, message rendering

local spinner = require("utils.ai.spinner")

local M = {}

local default_config = {
    split_width = 80,
    filetype = "markdown",
    title = "AI Chat",
}

local config = vim.deepcopy(default_config)

local state = {
    buf_id = nil,
    win_id = nil,
    is_streaming = false,
    spinner = nil,
    spinner_line = nil, -- 0-indexed line where the spinner lives
}

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

local function buf_is_valid()
    return state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id)
end

local function win_is_valid()
    return state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

local function create_buf()
    if buf_is_valid() then
        return state.buf_id
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = config.filetype
    vim.api.nvim_buf_set_name(buf, "ai-chat")

    state.buf_id = buf
    return buf
end

local function scroll_to_bottom()
    if not win_is_valid() then return end
    local line_count = vim.api.nvim_buf_line_count(state.buf_id)
    vim.api.nvim_win_set_cursor(state.win_id, { line_count, 0 })
end

--- Run a function with the buffer temporarily modifiable
local function with_modifiable(fn)
    if not buf_is_valid() then return end
    vim.bo[state.buf_id].modifiable = true
    fn()
    vim.bo[state.buf_id].modifiable = false
end

--- Stop the spinner and remove the spinner line from the buffer
local function stop_spinner()
    if state.spinner then
        state.spinner.stop()
        state.spinner = nil
    end

    if state.spinner_line and buf_is_valid() then
        with_modifiable(function()
            vim.api.nvim_buf_set_lines(state.buf_id, state.spinner_line, state.spinner_line + 1, false, {})
        end)
    end

    state.spinner_line = nil
end

--- Start an animated spinner on the last line of the chat buffer
local function start_spinner()
    if not buf_is_valid() then return end

    with_modifiable(function()
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        vim.api.nvim_buf_set_lines(state.buf_id, line_count, line_count, false, { "" })
        state.spinner_line = line_count
    end)
    scroll_to_bottom()

    state.spinner = spinner.create({
        on_frame = function(frame)
            if not buf_is_valid() or not state.spinner_line then
                stop_spinner()
                return
            end
            with_modifiable(function()
                vim.api.nvim_buf_set_lines(
                    state.buf_id,
                    state.spinner_line,
                    state.spinner_line + 1,
                    false,
                    { frame .. " Thinking..." }
                )
            end)
        end,
    })
    state.spinner.start()
end

function M.open()
    if win_is_valid() then
        vim.api.nvim_set_current_win(state.win_id)
        return
    end

    local buf = create_buf()

    -- Open a vertical split on the right
    vim.cmd("botright vsplit")
    state.win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win_id, buf)
    vim.api.nvim_win_set_width(state.win_id, config.split_width)

    -- Window-local options
    vim.wo[state.win_id].number = false
    vim.wo[state.win_id].relativenumber = false
    vim.wo[state.win_id].signcolumn = "no"
    vim.wo[state.win_id].wrap = true
    vim.wo[state.win_id].linebreak = true
    vim.wo[state.win_id].cursorline = false

    scroll_to_bottom()

    -- Return focus to the previous window
    vim.cmd("wincmd p")
end

function M.close()
    if win_is_valid() then
        vim.api.nvim_win_close(state.win_id, false)
        state.win_id = nil
    end
end

function M.toggle()
    if win_is_valid() then
        M.close()
    else
        M.open()
    end
end

function M.is_open()
    return win_is_valid()
end

--- Append lines of text to the chat buffer
--- @param lines string[] Lines to append
local function append_lines(lines)
    if not buf_is_valid() then return end

    with_modifiable(function()
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        local first_line = vim.api.nvim_buf_get_lines(state.buf_id, 0, 1, false)
        if line_count == 1 and first_line[1] == "" then
            vim.api.nvim_buf_set_lines(state.buf_id, 0, 1, false, lines)
        else
            vim.api.nvim_buf_set_lines(state.buf_id, line_count, line_count, false, lines)
        end
    end)
    scroll_to_bottom()
end

--- Append a user message to the chat buffer
--- @param text string The user's message
function M.append_user_message(text)
    local lines = { "---", "", "**You:**", "" }
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    append_lines(lines)
end

--- Start an assistant response block in the chat buffer
function M.start_assistant_message()
    append_lines({ "**Assistant:**", "" })
    state.is_streaming = true
    start_spinner()
end

--- Append a streaming text delta to the current assistant response
--- @param text string The text chunk to append
function M.append_delta(text)
    if not buf_is_valid() then return end

    -- On first delta, kill the spinner
    if state.spinner then
        stop_spinner()
    end

    -- Split delta by newlines
    local parts = {}
    local i = 1
    while i <= #text do
        local nl = text:find("\n", i, true)
        if nl then
            table.insert(parts, text:sub(i, nl - 1))
            i = nl + 1
        else
            table.insert(parts, text:sub(i))
            i = #text + 1
        end
    end
    if text:sub(-1) == "\n" then
        table.insert(parts, "")
    end

    if #parts == 0 then
        return
    end

    with_modifiable(function()
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        local last_line = vim.api.nvim_buf_get_lines(state.buf_id, line_count - 1, line_count, false)[1] or ""

        local new_last = last_line .. parts[1]
        vim.api.nvim_buf_set_lines(state.buf_id, line_count - 1, line_count, false, { new_last })

        if #parts > 1 then
            local new_lines = {}
            for j = 2, #parts do
                table.insert(new_lines, parts[j])
            end
            local updated_count = vim.api.nvim_buf_line_count(state.buf_id)
            vim.api.nvim_buf_set_lines(state.buf_id, updated_count, updated_count, false, new_lines)
        end
    end)
    scroll_to_bottom()
end

--- Finish the current assistant response
function M.finish_assistant_message()
    stop_spinner()
    append_lines({ "", "" })
    state.is_streaming = false
end

--- Append a complete assistant message (for re-rendering saved conversations)
--- @param text string The assistant's full response
function M.append_assistant_content(text)
    local lines = { "**Assistant:**", "" }
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    append_lines(lines)
end

--- Show an error in the chat buffer
--- @param msg string Error message
function M.append_error(msg)
    stop_spinner()
    append_lines({ "", "**Error:** " .. msg, "" })
    state.is_streaming = false
end

--- Clear the chat buffer
function M.clear()
    stop_spinner()
    if not buf_is_valid() then return end
    with_modifiable(function()
        vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, { "" })
    end)
    state.is_streaming = false
end

--- Start the spinner (public, for tool-use gaps)
function M.show_spinner()
    if not state.spinner then
        start_spinner()
    end
end

--- Stop the spinner (public, for tool-use gaps)
function M.hide_spinner()
    if state.spinner then
        stop_spinner()
    end
end

function M.is_streaming()
    return state.is_streaming
end

function M.get_state()
    return vim.deepcopy(state)
end

return M
