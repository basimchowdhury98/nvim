-- utils/ai/init.lua
-- AI chat plugin - public API, setup, keymaps

local api = require("utils.ai.api")
local chat = require("utils.ai.chat")
local input = require("utils.ai.input")
local debug = require("utils.ai.debug")
local M = {}

local default_config = {
    api = {},
    chat = {},
    input = {},
    keymaps = {
        toggle = "<leader>it",
        send = "<leader>io",
        clear = "<leader>ic",
        cancel = "<leader>ix",
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

--- Check if project changed and clear the chat panel if needed
--- @return boolean true if project changed
local function sync_project()
    local current = get_project()
    local changed = last_project and last_project ~= current
    if changed then
        debug.log("Project changed from " .. last_project .. " to " .. current)
        -- Clear the panel since we only show the latest Q&A
        chat.clear()
    end
    last_project = current
    return changed
end

--- Format a visual selection as a quoted context block for the API message
--- @param selection table {filename, start_line, end_line, lang, text}
--- @return string
local function format_quoted_context(selection)
    local header = string.format(
        "[Referring to %s:%d-%d]",
        selection.filename,
        selection.start_line,
        selection.end_line
    )
    local fence_lang = selection.lang ~= "" and selection.lang or ""
    return header .. "\n```" .. fence_lang .. "\n" .. selection.text .. "\n```"
end

--- Send a user message and stream the AI response
--- @param text string The user's message
--- @param selection table|nil Optional visual selection to include as quoted context
local function send_message(text, selection)
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

    -- Build the content that goes to the API (with quoted context if any)
    local api_content = text
    if selection then
        api_content = format_quoted_context(selection) .. "\n\n" .. text
    end

    -- Store the full message with quoted context in conversation history
    table.insert(session.conversation, { role = "user", content = api_content })

    -- Build the full messages array with fresh buffer context
    local api_messages = build_api_messages()

    -- Clear the chat panel and show only this exchange
    chat.clear()
    local display_text = text
    if selection then
        display_text = string.format("> %s:%d-%d\n\n%s",
            selection.filename, selection.start_line, selection.end_line, text)
    end
    chat.append_user_message(display_text)

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

            -- Auto-yank the first <code> block into the unnamed register
            local code = full_response:match("<code>\n?(.-)</code>")
            if code then
                -- Safety net: strip fences/backticks/quotes the LLM may have added
                code = code:gsub("```[^\n]*\n?", "")
                code = code:gsub("^\n+", ""):gsub("\n+$", "")
                code = code:gsub("^`+", ""):gsub("`+$", "")
                code = code:gsub('^"', ""):gsub('"$', "")
                code = code:gsub("^'", ""):gsub("'$", "")
                vim.fn.setreg('"', code)
                vim.fn.setreg('0', code)
                vim.fn.setreg('+', code)
                debug.log("Auto-yanked first code block (" .. #code .. " chars)")
            end
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

--- Capture the current visual selection range and text for use as quoted context
--- @return table|nil {filename, start_line, end_line, lang, text} or nil if not in visual mode
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
        filename = vim.api.nvim_buf_get_name(buf),
        start_line = start_row + 1, -- 1-indexed for display
        end_line = end_row + 1,
        lang = vim.bo[buf].filetype or "",
        text = text,
    }
end

--- Open the input popup and send the message on submit.
--- If called from visual mode, the selection is included as quoted context.
--- @return number buf_id The buffer id of the input popup
function M.prompt()
    sync_project()
    local selection = get_visual_selection()

    return input.open(function(text)
        send_message(text, selection)
    end)
end

--- Toggle the chat panel
function M.toggle()
    sync_project()
    chat.toggle()
end

--- Kill any in-flight request (no UI side-effects)
local function kill_request()
    if cancel_request then
        cancel_request()
        cancel_request = nil
        return true
    end
    return false
end

--- Close the chat and clear conversation for the current project
function M.clear()
    kill_request()
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
    kill_request()
    chat.clear()
    chat.close()
    sessions = {}
    last_project = nil
    api.reset_alt()
end

--- Interrupt the current in-flight request
function M.cancel()
    if not kill_request() then
        return
    end
    -- Discard the pending user message from history
    local session = get_session()
    if #session.conversation > 0 and session.conversation[#session.conversation].role == "user" then
        table.remove(session.conversation)
    end
    chat.append_interrupted()
    debug.log("Request interrupted by user")
end

--- Send a message with an optional quoted selection (exposed for testing)
--- @param text string
--- @param selection table|nil
function M.send(text, selection)
    send_message(text, selection)
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})

    api.setup(config.api)
    chat.setup(config.chat)
    input.setup(config.input)

    local map = vim.keymap.set

    map("n", config.keymaps.toggle, M.toggle, { desc = "AI: Toggle chat panel" })
    map("n", config.keymaps.send, M.prompt, { desc = "AI: Send message" })
    map("v", config.keymaps.send, M.prompt, { desc = "AI: Send message with selection context" })
    map("n", config.keymaps.clear, M.clear, { desc = "AI: Clear conversation" })
    map("n", config.keymaps.cancel, M.cancel, { desc = "AI: Interrupt streaming response" })

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

    vim.api.nvim_create_user_command("AIDebugLogs", function()
        local log_file = debug.get_log_dir() .. "/" .. os.date("%Y-%m-%d") .. ".log"
        if vim.fn.filereadable(log_file) == 0 then
            vim.notify("AI: No log file for today", vim.log.levels.WARN)
            return
        end
        vim.cmd("vsplit " .. vim.fn.fnameescape(log_file))
        vim.bo.modifiable = false
        vim.bo.readonly = true
    end, { desc = "AI: Open today's debug log in a split" })

    vim.api.nvim_create_user_command("AIAlt", function()
        api.toggle_alt()
    end, { desc = "AI: Toggle alt OpenAI-compatible provider (work mode only)" })
end

return M
