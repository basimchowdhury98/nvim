-- utils/ai/init.lua
-- AI chat plugin - public API, setup, keymaps

local api = require("utils.ai.api")
local chat = require("utils.ai.chat")
local input = require("utils.ai.input")
local debug = require("utils.ai.debug")
local lag = require("utils.ai.lag")
local usage = require("utils.ai.usage")
local M = {}

local default_config = {
    api = {},
    chat = {},
    input = {},
    keymaps = {
        toggle = "<leader>it",
        send = "<leader>io",
        cancel = "<leader>ix",
        continue_response = "<leader>in",
        lag_revert = "<leader>lr",
        lag_accept = "<leader>la",
        toggle_thinking = "<leader>ir",
    },
}

local config = vim.deepcopy(default_config)

-- Whether the AI system is active (started via the onboarding prompt)
local active = false

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
    local thinking_chunks = {}

    cancel_request = api.stream(
        api_messages,
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)
            chat.append_delta(delta)
        end,
        -- on_done
        function(metadata)
            cancel_request = nil
            local full_response = table.concat(response_chunks, "")
            local full_thinking = table.concat(thinking_chunks, "")
            if #full_thinking > 0 then
                debug.log("AI thinking:\n" .. full_thinking)
            end
            debug.log("AI response:\n" .. full_response)

            if full_response == "" then
                chat.append_error("Empty response from provider")
                table.remove(session.conversation)
            else
                local msg = { role = "assistant", content = full_response }
                if #full_thinking > 0 then
                    msg.thinking = full_thinking
                end
                table.insert(session.conversation, msg)
                chat.finish_assistant_message(full_thinking)
            end
            usage.add(metadata)
        end,
        -- on_error
        function(err)
            chat.append_error(err)
            vim.notify("AI: " .. err, vim.log.levels.ERROR)
            -- Remove the failed user message from history
            table.remove(session.conversation)
            cancel_request = nil
        end,
        {
            source = "chat",
            on_thinking = function(chunk)
                table.insert(thinking_chunks, chunk)
            end,
        }
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

--- Activate the AI system (called after onboarding prompt is answered)
local function activate()
    active = true
    debug.log("AI system activated")
end

--- Open the input popup and send the message on submit.
--- If the system is not active, shows the onboarding prompt.
--- If called from visual mode, the selection is included as quoted context.
--- @return number buf_id The buffer id of the input popup
function M.prompt()
    sync_project()
    local selection = get_visual_selection()

    if not active then
        return input.open(function(text)
            activate()
            local prefixed = "What we are working on this session: " .. text
            send_message(prefixed, selection)
            lag.start(M.build_context_block, M.get_session)
            usage.update_tabline()
        end, { title = " What are we working on? " })
    end

    return input.open(function(text)
        send_message(text, selection)
    end)
end

--- Toggle the chat panel (no-op when inactive)
function M.toggle()
    if not active then
        return
    end
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

--- Stop the AI system: kill requests, stop lag, clear chat, deactivate
function M.stop()
    kill_request()
    lag.stop()
    chat.clear()
    chat.close()
    local session = get_session()
    session.conversation = {}
    usage.reset()
    active = false
    last_project = get_project()
    vim.notify("AI: Session ended")
end

--- Reset all sessions (for testing)
function M.reset_all()
    kill_request()
    chat.clear()
    chat.close()
    sessions = {}
    last_project = nil
    active = false
    api.reset_alt()
    lag.reset()
    usage.reset()
end

--- Interrupt the current in-flight request (no-op when inactive)
function M.cancel()
    if not active then
        return
    end

    local cancelled_chat = kill_request()
    local cancelled_lag = lag.cancel()

    if not cancelled_chat and not cancelled_lag then
        return
    end

    if cancelled_chat then
        -- Discard the pending user message from history
        local session = get_session()
        if #session.conversation > 0 and session.conversation[#session.conversation].role == "user" then
            table.remove(session.conversation)
        end
        chat.append_interrupted()
    end

    debug.log("Request interrupted by user (chat=" .. tostring(cancelled_chat) .. ", lag=" .. tostring(cancelled_lag) .. ")")
end

--- Send a message with an optional quoted selection (exposed for testing)
--- @param text string
--- @param selection table|nil
function M.send(text, selection)
    send_message(text, selection)
end

--- Toggle visibility of thinking/reasoning blocks in the chat (no-op when inactive)
function M.toggle_thinking()
    if not active then
        return
    end
    chat.toggle_thinking()
end

--- Send a "continue" message to ask the LLM to keep going (no-op when inactive)
function M.continue_response()
    if not active then
        return
    end
    send_message("continue")
end

-- Expose for lag mode and context dump
M.build_context_block = build_context_block
M.get_session = get_session

--- Whether the AI system is currently active
--- @return boolean
function M.is_active()
    return active
end

--- Activate the AI system without the onboarding prompt (for testing)
function M.activate()
    activate()
end

--- Build a full snapshot of all tracked plugin state.
--- @return table
function M.build_state_snapshot()
    local session = get_session()
    local project_bufs = get_project_buffers()
    local buf_names = {}
    for _, buf in ipairs(project_bufs) do
        table.insert(buf_names, vim.api.nvim_buf_get_name(buf))
    end

    return {
        project = get_project(),
        active = active,
        provider = api.get_provider(),
        conversation = vim.deepcopy(session.conversation),
        buffer_context = build_context_block(),
        project_buffers = buf_names,
        lag = lag.get_all_state(),
        usage = usage.get_totals(),
    }
end

--- Dump full plugin state to a file in the log directory.
function M.context_dump()
    debug.write_dump(M.build_state_snapshot())
end

--- Format an API request body as a readable string.
--- @param request table from api.get_last_*_request()
--- @return string
local function format_request_dump(request)
    local lines = {}
    table.insert(lines, "Provider: " .. request.provider)
    table.insert(lines, "Endpoint: " .. request.endpoint)
    table.insert(lines, "Model: " .. request.model)
    table.insert(lines, "")

    if type(request.body) == "string" then
        table.insert(lines, "--- PROMPT (flattened text) ---")
        table.insert(lines, request.body)
    else
        table.insert(lines, "--- REQUEST BODY (JSON) ---")
        local json = vim.fn.json_encode(request.body)
        local ok, formatted = pcall(vim.fn.json_decode, json)
        if ok then
            table.insert(lines, vim.inspect(formatted))
        else
            table.insert(lines, json)
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Dump the last chat API payload to a file.
function M.chat_dump()
    local request = api.get_last_chat_request()
    if not request then
        vim.notify("AI: No chat request sent yet", vim.log.levels.WARN)
        return
    end
    debug.write_dump_file(format_request_dump(request), "chat_dump")
end

--- Dump the last lag API payload to a file.
function M.lag_dump()
    local request = api.get_last_lag_request()
    if not request then
        vim.notify("AI: No lag request sent yet", vim.log.levels.WARN)
        return
    end
    debug.write_dump_file(format_request_dump(request), "lag_dump")
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
    map("n", config.keymaps.cancel, M.cancel, { desc = "AI: Interrupt streaming response" })
    map("n", config.keymaps.continue_response, M.continue_response, { desc = "AI: Continue response" })
    map("n", config.keymaps.toggle_thinking, M.toggle_thinking, { desc = "AI: Toggle thinking/reasoning visibility" })
    map("n", config.keymaps.lag_revert, function()
        if not active then
            return
        end
        lag.revert()
    end, { desc = "Lag: Revert nearest modification" })
    map("n", config.keymaps.lag_accept, function()
        if not active then
            return
        end
        lag.accept()
    end, { desc = "Lag: Accept nearest modification" })

    vim.api.nvim_create_user_command("AIContextDump", function()
        M.context_dump()
    end, { desc = "AI: Dump full plugin state to log directory" })

    vim.api.nvim_create_user_command("AIChatDump", function()
        M.chat_dump()
    end, { desc = "AI: Dump exact chat API payload" })

    vim.api.nvim_create_user_command("AILagDump", function()
        M.lag_dump()
    end, { desc = "AI: Dump exact lag API payload (stubbed diff)" })

    vim.api.nvim_create_user_command("AIDebugLogs", function()
        local log_file = debug.get_log_dir() .. "/" .. os.date("%Y-%m-%d") .. ".log"
        if vim.fn.filereadable(log_file) == 0 then
            vim.notify("AI: No log file for today", vim.log.levels.WARN)
            return
        end
        vim.cmd("vsplit " .. vim.fn.fnameescape(log_file))
        vim.bo.modifiable = false
        vim.bo.readonly = true
        vim.wo.wrap = true
    end, { desc = "AI: Open today's debug log in a split" })

    vim.api.nvim_create_user_command("AIAlt", function()
        api.toggle_alt()
    end, { desc = "AI: Toggle alt OpenAI-compatible provider (work mode only)" })

    vim.api.nvim_create_user_command("AIStop", function()
        M.stop()
    end, { desc = "AI: Stop everything and deactivate" })

    vim.api.nvim_create_user_command("AILagAcceptAll", function()
        if not active then
            return
        end
        lag.clear()
    end, { desc = "Lag: Accept all modifications" })
end

return M
