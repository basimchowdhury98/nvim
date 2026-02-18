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
    },
}

local config = vim.deepcopy(default_config)

-- Project-scoped sessions keyed by cwd
-- Each session: { conversation = {} }
local sessions = {}

-- Handle to cancel in-flight requests (global, only one request at a time)
local cancel_request = nil

-- Track the last active project to detect switches
local last_project = nil

-- Patterns to exclude from buffer tracking (matched against filename, case-insensitive)
local exclude_patterns = {
    "appsettings",
    "env",
}

--- Get or create the session for the current working directory
--- @return table session
local function get_session()
    local cwd = vim.fn.getcwd()
    if not sessions[cwd] then
        sessions[cwd] = {
            conversation = {},
        }
        debug.log("Created new session for project: " .. cwd)
    end
    return sessions[cwd]
end

--- Get the current project path
--- @return string
local function get_project()
    return vim.fn.getcwd()
end

--- Check whether a buffer should be included as context
--- @param buf number
--- @return boolean
local function is_includable(buf)
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
    -- Must be within the current project directory
    local cwd = vim.fn.getcwd()
    if not name:find(cwd, 1, true) then
        return false
    end
    return true
end

--- Get all open buffers that are within the current project
--- @return number[] buffer ids
local function get_project_buffers()
    local bufs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and is_includable(buf) then
            table.insert(bufs, buf)
        end
    end
    return bufs
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

--- Build a context block from all open project buffers (reads live content)
--- @return string|nil
local function build_context_block()
    local parts = {}
    for _, buf in ipairs(get_project_buffers()) do
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
    local session = get_session()
    local ctx = build_context_block()
    local messages = {}
    local context_injected = false
    for _, msg in ipairs(session.conversation) do
        if not context_injected and msg.role == "user" and ctx then
            table.insert(messages, { role = "user", content = ctx .. "\n\n" .. msg.content })
            context_injected = true
        else
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    return messages
end

--- Re-render the chat buffer with the current session's conversation
local function render_chat()
    chat.clear()
    local session = get_session()
    for _, msg in ipairs(session.conversation) do
        if msg.role == "user" then
            chat.append_user_message(msg.content)
        else
            chat.append_assistant_content(msg.content)
        end
    end
end

--- Check if project changed and re-render chat if needed
--- @return boolean true if project changed
local function sync_project()
    local current = get_project()
    local changed = last_project and last_project ~= current
    if changed then
        debug.log("Project changed from " .. last_project .. " to " .. current)
        -- Always re-render (clears old content even if chat is closed)
        render_chat()
    end
    last_project = current
    return changed
end

--- Send a user message and stream the AI response
--- @param text string The user's message
local function send_message(text)
    debug.log("send_message called with: " .. text:sub(1, 100))

    if chat.is_streaming() then
        vim.notify("AI: Already streaming a response, please wait", vim.log.levels.WARN)
        return
    end

    -- Sync project state (re-render if changed)
    sync_project()

    -- Make sure chat panel is open
    if not chat.is_open() then
        chat.open()
    end

    local session = get_session()

    -- Store raw user message (no context baked in)
    table.insert(session.conversation, { role = "user", content = text })

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
            debug.log("AI response:\n" .. full_response)
            table.insert(session.conversation, { role = "assistant", content = full_response })
            chat.finish_assistant_message()
            cancel_request = nil
        end,
        -- on_error
        function(err)
            chat.append_error(err)
            vim.notify("AI: " .. err, vim.log.levels.ERROR)
            -- Remove the failed user message from history
            table.remove(session.conversation)
            cancel_request = nil
        end
    )
end

-- Number of lines to capture before/after selection for context
local SURROUNDING_LINES = 5

--- Capture the current visual selection range and text
--- @return table|nil {buf, start_row, start_col, end_row, end_col, text, lines_before, lines_after} or nil if not in visual mode
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

    -- Capture surrounding lines for context
    local total_lines = vim.api.nvim_buf_line_count(buf)
    local before_start = math.max(0, start_row - SURROUNDING_LINES)
    local after_end = math.min(total_lines, end_row + 1 + SURROUNDING_LINES)

    local lines_before = vim.api.nvim_buf_get_lines(buf, before_start, start_row, false)
    local lines_after = vim.api.nvim_buf_get_lines(buf, end_row + 1, after_end, false)

    -- Detect indentation from the closest non-empty surrounding line
    -- Prefer the line immediately after, then immediately before
    local indent = ""
    for _, line in ipairs(lines_after) do
        if line:match("%S") then
            indent = line:match("^(%s*)") or ""
            break
        end
    end
    if indent == "" then
        for i = #lines_before, 1, -1 do
            local line = lines_before[i]
            if line:match("%S") then
                indent = line:match("^(%s*)") or ""
                break
            end
        end
    end

    return {
        buf = buf,
        filename = vim.api.nvim_buf_get_name(buf),
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        text = text,
        lines_before = table.concat(lines_before, "\n"),
        lines_after = table.concat(lines_after, "\n"),
        indent = indent,
    }
end

--- Open the input popup and send the message on submit
--- If called from visual mode, opens inline mode instead
--- @return number buf_id The buffer id of the input popup
function M.prompt()
    sync_project()
    local selection = get_visual_selection()
    local session = get_session()

    if selection then
        -- Visual mode: inline agentic coding
        return input.open(function(instruction)
            inline.execute(selection, instruction, build_context_block(), session.conversation)
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
    sync_project()
    chat.toggle()
end

--- Close the chat and clear conversation for the current project
function M.clear()
    if cancel_request then
        cancel_request()
        cancel_request = nil
    end
    chat.clear()
    local session = get_session()
    session.conversation = {}
    chat.close()
    -- Reset last_project so next toggle doesn't think we switched
    last_project = get_project()
    vim.notify("AI: Conversation cleared for " .. get_project())
end

--- Reset all sessions (for testing)
function M.reset_all()
    if cancel_request then
        cancel_request()
        cancel_request = nil
    end
    chat.clear()
    chat.close()
    sessions = {}
    last_project = nil
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

    vim.api.nvim_create_user_command("AIFiles", function()
        local bufs = get_project_buffers()
        if #bufs == 0 then
            vim.notify("AI: No project files open")
            return
        end
        local names = {}
        for _, buf in ipairs(bufs) do
            table.insert(names, vim.api.nvim_buf_get_name(buf))
        end
        vim.notify("AI project files:\n" .. table.concat(names, "\n"))
    end, { desc = "AI: List open project files" })

    vim.api.nvim_create_user_command("AIProject", function()
        vim.notify("AI project: " .. get_project())
    end, { desc = "AI: Show current project path" })

    vim.api.nvim_create_user_command("AIDebugPath", function()
        vim.notify("AI log directory: " .. debug.get_log_dir())
    end, { desc = "AI: Show debug log directory" })
end

return M
