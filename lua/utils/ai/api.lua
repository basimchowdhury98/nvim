-- api.lua
-- AI provider: opencode CLI (default) or Anthropic API (when AI_WORK=true)

local M = {}
local debug = require("utils.ai.debug")
local chat = require("utils.ai.chat")

local default_config = {
    -- Anthropic direct API settings (used when AI_WORK is set)
    api_key_env = "ANTHROPIC_API_KEY",
    model = "claude-opus-4-20250514",
    max_tokens = 4096,
    endpoint = "https://api.anthropic.com/v1/messages",
    api_version = "2023-06-01",
    system_prompt = "You are a helpful coding assistant. Be concise and direct.",
}

local config = vim.deepcopy(default_config)

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

--- Check if we should use the Anthropic API directly (work mode)
local function is_work_mode()
    local val = os.getenv("AI_WORK")
    return val and val ~= "" and val ~= "false" and val ~= "0"
end

local function get_api_key()
    local key = os.getenv(config.api_key_env)
    if not key or key == "" then
        vim.notify("AI: " .. config.api_key_env .. " env var not set", vim.log.levels.ERROR)
        return nil
    end
    return key
end

-- ============================================================
-- Provider: opencode CLI
-- ============================================================
--
local opencode_cli_name = "7619b34b-opencode-d0a72d8a"

--- Build the user prompt from conversation messages.
--- opencode run doesn't support multi-turn, so we flatten the
--- conversation into a single prompt with context.
--- @param messages table[]
--- @return string
local function build_opencode_prompt(messages)
    local parts = {}
    for _, msg in ipairs(messages) do
        if msg.role == "user" then
            table.insert(parts, "User: " .. msg.content)
        elseif msg.role == "assistant" then
            table.insert(parts, "Assistant: " .. msg.content)
        end
    end
    table.insert(parts, "Assistant:")
    return table.concat(parts, "\n\n")
end

--- @param messages table[]
--- @param on_delta fun(text: string)
--- @param on_done fun()
--- @param on_error fun(err: string)
--- @return fun()|nil cancel
local function stream_opencode(messages, on_delta, on_done, on_error)
    debug.log("using opencode provider")

    local prompt = build_opencode_prompt(messages)
    debug.log("opencode prompt length: " .. #prompt)

    -- Write prompt to temp file to avoid shell escaping issues
    local tmp = vim.fn.tempname()
    local f = io.open(tmp, "w")
    if not f then
        on_error("Failed to create temp file")
        return nil
    end
    f:write(prompt)
    f:close()

    local stderr_chunks = {}

    -- Use cmd.exe /c to handle piping on Windows
    local shell_cmd
    if vim.fn.has("win32") == 1 then
        shell_cmd = { "cmd", "/c", "type " .. tmp .. " | " .. opencode_cli_name .. " run --format json --title nvim-ai" }
    else
        shell_cmd = { "sh", "-c", "cat " .. tmp .. " | " .. opencode_cli_name .. " run --format json --title nvim-ai" }
    end

    debug.log("Starting opencode job...")

    local job_id = vim.fn.jobstart(shell_cmd, {
        on_stdout = function(_, data, _)
            debug.log("on_stdout called, lines: " .. #data)
            for _, line in ipairs(data) do
                if line == "" then goto continue end

                debug.log("stdout line: " .. line:sub(1, 200))

                local ok, event = pcall(vim.fn.json_decode, line)
                if not ok then
                    debug.log("JSON decode failed: " .. tostring(event))
                    goto continue
                end

                debug.log("event type: " .. tostring(event.type))

                if event.type == "text" and event.part and event.part.text then
                    vim.schedule(function()
                        on_delta(event.part.text)
                    end)
                elseif event.type == "tool_use" and event.part then
                    local tool = event.part.tool or "unknown"
                    debug.log("tool_use: " .. tool)
                    vim.schedule(function()
                        on_delta("\n\n*Using tool: " .. tool .. "...*\n\n")
                        chat.show_spinner()
                    end)
                elseif event.type == "step_finish" then
                    local reason = event.part and event.part.reason or "unknown"
                    debug.log("step_finish received, reason: " .. reason)
                    -- Only finish on "stop", not "tool-calls" (intermediate step)
                    if reason == "stop" then
                        vim.schedule(function()
                            on_done()
                            os.remove(tmp)
                        end)
                        return
                    end
                end

                ::continue::
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    debug.log("stderr: " .. line)
                    table.insert(stderr_chunks, line)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            debug.log("opencode exited with code: " .. exit_code)
            os.remove(tmp)
            if exit_code ~= 0 then
                vim.schedule(function()
                    local stderr_msg = table.concat(stderr_chunks, "\n")
                    on_error("opencode exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            else
                -- Fallback: if process exits cleanly but we never got a
                -- step_finish with reason "stop", finish gracefully
                vim.schedule(function()
                    on_done()
                end)
            end
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    debug.log("jobstart returned: " .. tostring(job_id))

    if job_id <= 0 then
        on_error("Failed to start opencode (is it installed?)")
        os.remove(tmp)
        return nil
    end

    return function()
        vim.fn.jobstop(job_id)
        os.remove(tmp)
    end
end

-- ============================================================
-- Provider: Anthropic API (direct curl)
-- ============================================================

--- @param messages table[]
--- @param on_delta fun(text: string)
--- @param on_done fun()
--- @param on_error fun(err: string)
--- @return fun()|nil cancel
local function stream_anthropic(messages, on_delta, on_done, on_error)
    debug.log("using anthropic provider")

    local api_key = get_api_key()
    if not api_key then
        debug.log("API key not found!")
        on_error("API key not found")
        return nil
    end
    debug.log("API key found (length: " .. #api_key .. ")")

    local body = vim.fn.json_encode({
        model = config.model,
        max_tokens = config.max_tokens,
        system = config.system_prompt,
        stream = true,
        messages = messages,
        tools = {
            {
                type = "web_search_20250305",
                name = "web_search",
                max_uses = 5,
            },
        },
    })

    debug.log("Request body length: " .. #body)
    debug.log("Model: " .. config.model)
    debug.log("Endpoint: " .. config.endpoint)

    local tmp = vim.fn.tempname()
    local f = io.open(tmp, "w")
    if not f then
        debug.log("Failed to create temp file: " .. tmp)
        on_error("Failed to create temp file")
        return nil
    end
    f:write(body)
    f:close()
    debug.log("Wrote request body to: " .. tmp)

    local stderr_chunks = {}

    local curl_cmd = {
        "curl", "--silent", "--no-buffer",
        "-X", "POST",
        config.endpoint,
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. api_key,
        "-H", "anthropic-version: " .. config.api_version,
        "-d", "@" .. tmp,
    }
    debug.log("Starting curl job...")

    local job_id = vim.fn.jobstart(curl_cmd, {
        on_stdout = function(_, data, _)
            debug.log("on_stdout called, lines: " .. #data)
            for _, line in ipairs(data) do
                if line == "" then goto continue end

                debug.log("stdout line: " .. line:sub(1, 200))

                -- SSE format: lines starting with "data: "
                local json_str = line:match("^data: (.+)")
                if not json_str then
                    debug.log("line does not match SSE 'data: ' pattern")
                    goto continue
                end

                local ok, event = pcall(vim.fn.json_decode, json_str)
                if not ok then
                    debug.log("JSON decode failed: " .. tostring(event))
                    goto continue
                end

                debug.log("event type: " .. tostring(event.type))

                if event.type == "content_block_start" then
                    local block = event.content_block
                    if block and block.type == "server_tool_use" then
                        local tool = block.name or "unknown"
                        debug.log("server_tool_use: " .. tool)
                        vim.schedule(function()
                            on_delta("\n\n*Searching the web...*\n\n")
                            chat.show_spinner()
                        end)
                    elseif block and block.type == "web_search_tool_result" then
                        debug.log("web_search_tool_result received")
                        vim.schedule(function()
                            chat.hide_spinner()
                        end)
                    end
                elseif event.type == "content_block_delta" then
                    local delta = event.delta
                    if delta and delta.type == "text_delta" and delta.text then
                        vim.schedule(function()
                            on_delta(delta.text)
                        end)
                    end
                elseif event.type == "message_stop" then
                    debug.log("message_stop received")
                    vim.schedule(function()
                        on_done()
                        os.remove(tmp)
                    end)
                    return
                elseif event.type == "error" then
                    local msg = event.error and event.error.message or "Unknown API error"
                    debug.log("API error: " .. msg)
                    vim.schedule(function()
                        on_error(msg)
                        os.remove(tmp)
                    end)
                    return
                end

                ::continue::
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    debug.log("stderr: " .. line)
                    table.insert(stderr_chunks, line)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            debug.log("curl exited with code: " .. exit_code)
            os.remove(tmp)
            if exit_code ~= 0 then
                vim.schedule(function()
                    local stderr_msg = table.concat(stderr_chunks, "\n")
                    on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    debug.log("jobstart returned: " .. tostring(job_id))

    if job_id <= 0 then
        debug.log("jobstart FAILED")
        on_error("Failed to start curl (is curl installed?)")
        os.remove(tmp)
        return nil
    end

    return function()
        vim.fn.jobstop(job_id)
        os.remove(tmp)
    end
end

-- ============================================================
-- Provider: Anthropic API for inline editing (no tools, specialized prompt)
-- ============================================================

local inline_system_prompt = [[You are an inline code editor. You will receive:
1. A section of code that the user has highlighted (the "editable region")
2. The user's instruction for what to write or change
3. Optional context about other open files

Your task is to output ONLY the replacement code for the highlighted region.

CRITICAL RULES:
- Output ONLY raw code - your entire response will be inserted directly into the source file
- NEVER wrap output in markdown code fences (``` or cs``` or other code specific fences) this will break the code
- NEVER include explanations, comments about what you did, or any other text
- Be smart about what to preserve (e.g., keep a method signature if asked to implement the body)
- Match the existing code style (indentation, naming conventions, etc.)
- Respect the spacing provided in the edittable region because your output will replace it inline

If the user's instruction is not asking you to write or modify code (e.g., they're asking a question, requesting an explanation, or the instruction doesn't make sense as a code edit), output exactly this sentinel and nothing else:
__NO_INLINE_CODE_PROMPT__

Your response is directly inserted into code. No markdown. No fences. No explanation. Just code.]]

--- @param selected_text string The highlighted code region
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context
--- @param history table|nil Optional conversation history
--- @param on_delta fun(text: string) Called with each text chunk
--- @param on_done fun() Called when complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel
local function stream_inline_anthropic(selected_text, instruction, context, history, on_delta, on_done, on_error)
    debug.log("using anthropic provider for inline edit")

    local api_key = get_api_key()
    if not api_key then
        debug.log("API key not found!")
        on_error("API key not found")
        return nil
    end

    -- Build the user message with inline-specific content
    local user_content = "## Highlighted Code (editable region)\n```\n" .. selected_text .. "\n```\n\n"
    user_content = user_content .. "## Instruction\n" .. instruction

    if context then
        user_content = user_content .. "\n\n## Context (other open files)\n" .. context
    end

    -- Build messages array: conversation history + inline request
    local messages = {}
    if history and #history > 0 then
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    table.insert(messages, { role = "user", content = user_content })

    local body = vim.fn.json_encode({
        model = config.model,
        max_tokens = config.max_tokens,
        system = inline_system_prompt,
        stream = true,
        messages = messages,
        -- No tools for inline editing
    })

    debug.log("Inline request body length: " .. #body)

    local tmp = vim.fn.tempname()
    local f = io.open(tmp, "w")
    if not f then
        debug.log("Failed to create temp file: " .. tmp)
        on_error("Failed to create temp file")
        return nil
    end
    f:write(body)
    f:close()

    local stderr_chunks = {}

    local curl_cmd = {
        "curl", "--silent", "--no-buffer",
        "-X", "POST",
        config.endpoint,
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. api_key,
        "-H", "anthropic-version: " .. config.api_version,
        "-d", "@" .. tmp,
    }

    local job_id = vim.fn.jobstart(curl_cmd, {
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                if line == "" then goto continue end

                local json_str = line:match("^data: (.+)")
                if not json_str then goto continue end

                local ok, event = pcall(vim.fn.json_decode, json_str)
                if not ok then goto continue end

                if event.type == "content_block_delta" then
                    local delta = event.delta
                    if delta and delta.type == "text_delta" and delta.text then
                        vim.schedule(function()
                            on_delta(delta.text)
                        end)
                    end
                elseif event.type == "message_stop" then
                    vim.schedule(function()
                        on_done()
                        os.remove(tmp)
                    end)
                    return
                elseif event.type == "error" then
                    local msg = event.error and event.error.message or "Unknown API error"
                    vim.schedule(function()
                        on_error(msg)
                        os.remove(tmp)
                    end)
                    return
                end

                ::continue::
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    debug.log("stderr: " .. line)
                    table.insert(stderr_chunks, line)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            debug.log("inline curl exited with code: " .. exit_code)
            os.remove(tmp)
            if exit_code ~= 0 then
                vim.schedule(function()
                    local stderr_msg = table.concat(stderr_chunks, "\n")
                    on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if job_id <= 0 then
        on_error("Failed to start curl")
        os.remove(tmp)
        return nil
    end

    return function()
        vim.fn.jobstop(job_id)
        os.remove(tmp)
    end
end

--- Build an inline prompt for opencode
local function build_inline_opencode_prompt(selected_text, instruction, context, history)
    local parts = {
        "You are an inline code editor. Your response will be inserted DIRECTLY into a source file.",
        "",
        "CRITICAL: Output ONLY raw code. NEVER use markdown code fences (```). NEVER add explanations.",
        "Your entire response replaces the highlighted text in the editor.",
        "",
        "If the instruction is not asking for code, output exactly: __NO_INLINE_CODE_PROMPT__",
    }

    -- Include conversation history for context
    if history and #history > 0 then
        table.insert(parts, "")
        table.insert(parts, "## Conversation History")
        for _, msg in ipairs(history) do
            if msg.role == "user" then
                table.insert(parts, "User: " .. msg.content)
            elseif msg.role == "assistant" then
                table.insert(parts, "Assistant: " .. msg.content)
            end
            table.insert(parts, "")
        end
    end

    table.insert(parts, "## Highlighted Code (editable region)")
    table.insert(parts, "```")
    table.insert(parts, selected_text)
    table.insert(parts, "```")
    table.insert(parts, "")
    table.insert(parts, "## Instruction")
    table.insert(parts, instruction)

    if context then
        table.insert(parts, "")
        table.insert(parts, "## Context (other open files)")
        table.insert(parts, context)
    end
    table.insert(parts, "")
    table.insert(parts, "Replacement code (no markdown, no fences, no explanation):")
    return table.concat(parts, "\n")
end

--- @param selected_text string
--- @param instruction string
--- @param context string|nil
--- @param history table|nil
--- @param on_delta fun(text: string)
--- @param on_done fun()
--- @param on_error fun(err: string)
--- @return fun()|nil cancel
local function stream_inline_opencode(selected_text, instruction, context, history, on_delta, on_done, on_error)
    debug.log("using opencode provider for inline edit")

    local prompt = build_inline_opencode_prompt(selected_text, instruction, context, history)
    debug.log("inline opencode prompt length: " .. #prompt)

    local tmp = vim.fn.tempname()
    local f = io.open(tmp, "w")
    if not f then
        on_error("Failed to create temp file")
        return nil
    end
    f:write(prompt)
    f:close()

    local stderr_chunks = {}

    local shell_cmd
    if vim.fn.has("win32") == 1 then
        shell_cmd = { "cmd", "/c", "type " .. tmp .. " | " .. opencode_cli_name .. " run --format json --title nvim-ai-inline" }
    else
        shell_cmd = { "sh", "-c", "cat " .. tmp .. " | " .. opencode_cli_name .. " run --format json --title nvim-ai-inline" }
    end

    local job_id = vim.fn.jobstart(shell_cmd, {
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                if line == "" then goto continue end

                local ok, event = pcall(vim.fn.json_decode, line)
                if not ok then goto continue end

                if event.type == "text" and event.part and event.part.text then
                    vim.schedule(function()
                        on_delta(event.part.text)
                    end)
                elseif event.type == "step_finish" then
                    local reason = event.part and event.part.reason or "unknown"
                    if reason == "stop" then
                        vim.schedule(function()
                            on_done()
                            os.remove(tmp)
                        end)
                        return
                    end
                end

                ::continue::
            end
        end,
        on_stderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    table.insert(stderr_chunks, line)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            os.remove(tmp)
            if exit_code ~= 0 then
                vim.schedule(function()
                    local stderr_msg = table.concat(stderr_chunks, "\n")
                    on_error("opencode exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if job_id <= 0 then
        on_error("Failed to start opencode")
        os.remove(tmp)
        return nil
    end

    return function()
        vim.fn.jobstop(job_id)
        os.remove(tmp)
    end
end

-- ============================================================
-- Public API
-- ============================================================

--- Send a streaming inline edit request to the active provider
--- @param selected_text string The highlighted code region
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context
--- @param history table|nil Optional conversation history
--- @param on_delta fun(text: string) Called with each text chunk
--- @param on_done fun() Called when complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel
function M.inline_stream(selected_text, instruction, context, history, on_delta, on_done, on_error)
    debug.log("inline_stream() called")
    debug.log("Selected text length: " .. #selected_text)
    debug.log("Instruction: " .. instruction:sub(1, 100))
    debug.log("History length: " .. (history and #history or 0))

    if is_work_mode() then
        return stream_inline_anthropic(selected_text, instruction, context, history, on_delta, on_done, on_error)
    else
        return stream_inline_opencode(selected_text, instruction, context, history, on_delta, on_done, on_error)
    end
end

--- Send a streaming request to the active provider
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param on_delta fun(text: string) Called with each text chunk as it arrives
--- @param on_done fun() Called when the response is complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel Function to cancel the request, or nil on error
function M.stream(messages, on_delta, on_done, on_error)
    debug.log("stream() called with " .. #messages .. " messages")
    debug.log("AI_WORK=" .. tostring(os.getenv("AI_WORK")))

    if is_work_mode() then
        return stream_anthropic(messages, on_delta, on_done, on_error)
    else
        return stream_opencode(messages, on_delta, on_done, on_error)
    end
end

function M.get_provider()
    return is_work_mode() and "anthropic" or "opencode"
end

function M.get_config()
    return vim.deepcopy(config)
end

return M
