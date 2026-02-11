-- utils/ai/init.lua
-- AI chat plugin - public API, setup, keymaps

local api = require("utils.ai.api")
local chat = require("utils.ai.chat")
local input = require("utils.ai.input")
local debug = require("utils.ai.debug")
local inline = require("utils.ai.inline")

local M = {}

local default_config = {
    api = {},
    chat = {},
    input = {},
    keymaps = {
        toggle = "<leader>io",
        send = "<leader>ia",
        clear = "<leader>ic",
        debug = "<leader>id",
    },
}

local config = vim.deepcopy(default_config)

-- Conversation history for the current session (stores raw user/assistant text)
local conversation = {}

-- Handle to cancel in-flight requests
local cancel_request = nil

-- Ordered list of tracked buffer IDs for the current session
local tracked_bufs = {}

-- Autocmd group ID for BufEnter tracking (nil when no session)
local tracking_augroup = nil

-- Patterns to exclude from buffer tracking (matched against filename, case-insensitive)
local exclude_patterns = {
    "appsettings",
    "env",
}

--- Check whether a buffer should be tracked (real file, not chat/input)
--- @param buf number
--- @return boolean
local function is_trackable(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    if name == "" or ft == "" then
        return false
    end
    -- Skip special buffers (chat panel, popups, terminals, etc.)
    if bt ~= "" then
        return false
    end
    -- Check exclusion patterns
    local name_lower = name:lower()
    for _, pattern in ipairs(exclude_patterns) do
        if name_lower:find(pattern, 1, true) then
            return false
        end
    end
    return true
end

--- Add a buffer to the tracked set if not already present
--- @param buf number
local function track_buf(buf)
    if not is_trackable(buf) then
        return
    end
    for _, id in ipairs(tracked_bufs) do
        if id == buf then
            return
        end
    end
    table.insert(tracked_bufs, buf)
    debug.log("Tracking buffer: " .. vim.api.nvim_buf_get_name(buf))
end

--- Start the BufEnter autocmd that tracks visited buffers
local function start_tracking()
    if tracking_augroup then
        return
    end
    tracking_augroup = vim.api.nvim_create_augroup("AiChatBufTrack", { clear = true })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = tracking_augroup,
        callback = function(ev)
            track_buf(ev.buf)
        end,
    })
end

--- Stop the BufEnter autocmd
local function stop_tracking()
    if tracking_augroup then
        vim.api.nvim_del_augroup_by_id(tracking_augroup)
        tracking_augroup = nil
    end
end

--- Read the current content of a buffer and format it as a context block
--- @param buf number
--- @return string|nil
local function read_buf_context(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return nil
    end
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype
    if name == "" or ft == "" then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local content = table.concat(lines, "\n")

    if #content > 50000 then
        content = content:sub(1, 50000) .. "\n... (truncated)"
    end

    return string.format("Filename: %s\nLanguage: %s\n\n```%s\n%s\n```", name, ft, ft, content)
end

--- Build a context block from all tracked buffers (reads live content)
--- @return string|nil
local function build_context_block()
    local parts = {}
    for _, buf in ipairs(tracked_bufs) do
        local ctx = read_buf_context(buf)
        if ctx then
            table.insert(parts, ctx)
        end
    end
    if #parts == 0 then
        return nil
    end
    return "The user has the following files open:\n\n" .. table.concat(parts, "\n\n")
end

--- Build the messages array to send to the API.
--- Injects the latest buffer context into the first user message.
--- @return table[]
local function build_api_messages()
    local ctx = build_context_block()
    local messages = {}
    local context_injected = false
    for _, msg in ipairs(conversation) do
        if not context_injected and msg.role == "user" and ctx then
            table.insert(messages, { role = "user", content = ctx .. "\n\n" .. msg.content })
            context_injected = true
        else
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    return messages
end

--- Send a user message and stream the AI response
--- @param text string The user's message
local function send_message(text)
    debug.log("send_message called with: " .. text:sub(1, 100))

    if chat.is_streaming() then
        vim.notify("AI: Already streaming a response, please wait", vim.log.levels.WARN)
        return
    end

    -- Track the current buffer and start the BufEnter autocmd
    track_buf(vim.api.nvim_get_current_buf())
    start_tracking()

    -- Make sure chat panel is open
    if not chat.is_open() then
        chat.open()
    end

    -- Store raw user message (no context baked in)
    table.insert(conversation, { role = "user", content = text })

    -- Build the full messages array with fresh buffer context
    local api_messages = build_api_messages()

    -- Show user message in chat
    chat.append_user_message(text)

    -- Start assistant block
    chat.start_assistant_message()

    -- Track assistant response for conversation history
    local response_chunks = {}

    cancel_request = api.stream(
        api_messages,
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)
            chat.append_delta(delta)
        end,
        -- on_done
        function()
            local full_response = table.concat(response_chunks, "")
            table.insert(conversation, { role = "assistant", content = full_response })
            chat.finish_assistant_message()
            cancel_request = nil
        end,
        -- on_error
        function(err)
            chat.append_error(err)
            -- Remove the failed user message from history
            table.remove(conversation)
            cancel_request = nil
        end
    )
end

--- Capture the current visual selection range and text
--- @return table|nil {buf, start_row, start_col, end_row, end_col, text} or nil if not in visual mode
local function get_visual_selection()
    local mode = vim.fn.mode()
    if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
        return nil
    end

    -- Exit visual mode to set '< and '> marks
    vim.cmd('normal! "vy')

    local buf = vim.api.nvim_get_current_buf()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_row = start_pos[2] - 1 -- 0-indexed
    local start_col = start_pos[3] - 1
    local end_row = end_pos[2] - 1
    local end_col = end_pos[3]

    -- For linewise visual mode, select entire lines
    if mode == "V" then
        start_col = 0
        end_col = #vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1]
    end

    local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {})
    local text = table.concat(lines, "\n")

    return {
        buf = buf,
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        text = text,
    }
end

--- Open the input popup and send the message on submit
--- If called from visual mode, opens inline mode instead
--- @return number buf_id The buffer id of the input popup
function M.prompt()
    local selection = get_visual_selection()

    if selection then
        -- Visual mode: inline agentic coding
        return input.open(function(instruction)
            inline.execute(selection, instruction, build_context_block(), conversation)
        end, { title = " Inline Edit " })
    else
        -- Normal mode: regular chat
        return input.open(function(text)
            send_message(text)
        end)
    end
end

--- Toggle the chat panel
function M.toggle()
    chat.toggle()
end

--- Close the chat and clear conversation
function M.clear()
    if cancel_request then
        cancel_request()
        cancel_request = nil
    end
    chat.clear()
    conversation = {}
    tracked_bufs = {}
    stop_tracking()
    chat.close()
    vim.notify("AI: Conversation cleared")
end

--- Cancel the current in-flight request
function M.cancel()
    if cancel_request then
        cancel_request()
        cancel_request = nil
        chat.append_error("Request cancelled")
        vim.notify("AI: Request cancelled")
    end
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})

    api.setup(config.api)
    chat.setup(config.chat)
    input.setup(config.input)

    local map = vim.keymap.set

    map("n", config.keymaps.toggle, M.toggle, { desc = "AI: Toggle chat panel" })
    map("n", config.keymaps.send, M.prompt, { desc = "AI: Send message" })
    map("v", config.keymaps.send, M.prompt, { desc = "AI: Inline edit" })
    map("n", config.keymaps.clear, M.clear, { desc = "AI: Clear conversation" })
    map("n", config.keymaps.debug, debug.toggle, { desc = "AI: Toggle debug mode" })

    vim.api.nvim_create_user_command("AIFiles", function()
        if #tracked_bufs == 0 then
            vim.notify("AI: No files tracked")
            return
        end
        local names = {}
        for _, buf in ipairs(tracked_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                table.insert(names, vim.api.nvim_buf_get_name(buf))
            end
        end
        vim.notify("AI tracked files:\n" .. table.concat(names, "\n"))
    end, { desc = "AI: List tracked files" })
end

return M
