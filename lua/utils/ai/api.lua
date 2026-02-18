-- api.lua
-- AI provider: opencode CLI (default) or Anthropic API (when AI_WORK=true)

local M = {}
local debug = require("utils.ai.debug")
local chat = require("utils.ai.chat")
local job = require("utils.ai.job")

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

    local tmp, err = job.write_temp(prompt)
    if not tmp then
        on_error(err)
        return nil
    end

    local done_called = false

    local cancel = job.run({
        cmd = job.pipe_cmd(tmp, opencode_cli_name .. " run --format json --title nvim-ai"),
        temp_file = tmp,
        on_stdout = function(line)
            debug.log("stdout line: " .. line:sub(1, 200))

            local ok, event = pcall(vim.fn.json_decode, line)
            if not ok then
                debug.log("JSON decode failed: " .. tostring(event))
                return
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
                if reason == "stop" then
                    done_called = true
                    vim.schedule(function()
                        on_done()
                    end)
                end
            elseif event.type == "error" then
                local msg = event.part and event.part.message or event.message or "Unknown error"
                debug.log("opencode error: " .. msg)
                done_called = true
                vim.schedule(function()
                    on_error(msg)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            debug.log("opencode exited with code: " .. exit_code)
            if exit_code ~= 0 then
                vim.schedule(function()
                    on_error("opencode exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            elseif not done_called then
                vim.schedule(function()
                    on_done()
                end)
            end
        end,
    })

    if not cancel then
        on_error("Failed to start opencode (is it installed?)")
        return nil
    end

    return cancel
end

-- ============================================================
-- Provider: Anthropic API (direct curl)
-- ============================================================

--- Parse an SSE line and return the JSON payload or nil
--- @param line string
--- @return table|nil
local function parse_sse(line)
    local json_str = line:match("^data: (.+)")
    if not json_str then
        return nil
    end
    local ok, event = pcall(vim.fn.json_decode, json_str)
    if not ok then
        debug.log("JSON decode failed: " .. tostring(event))
        return nil
    end
    return event
end

--- Parse a plain JSON error response (non-SSE, returned on HTTP errors)
--- @param line string
--- @return string|nil error message if this is an error response
local function parse_json_error(line)
    -- Skip SSE lines - those are handled by parse_sse
    if line:match("^data:") or line:match("^event:") or line:match("^:") then
        return nil
    end
    -- Try to parse as JSON error response
    local ok, obj = pcall(vim.fn.json_decode, line)
    if not ok then
        return nil
    end
    -- Anthropic error format: {"type":"error","error":{"type":"...","message":"..."}}
    if obj.type == "error" and obj.error and obj.error.message then
        return obj.error.message
    end
    return nil
end

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

    local tmp, err = job.write_temp(body)
    if not tmp then
        debug.log("Failed to create temp file")
        on_error(err)
        return nil
    end
    debug.log("Wrote request body to: " .. tmp)

    local done_called = false

    local cancel = job.run({
        cmd = job.curl_cmd({
            endpoint = config.endpoint,
            api_key = api_key,
            api_version = config.api_version,
            body_file = tmp,
        }),
        temp_file = tmp,
        on_stdout = function(line)
            debug.log("stdout line: " .. line:sub(1, 200))

            -- Check for plain JSON error response (HTTP-level errors like 400, 401, 429)
            local json_err = parse_json_error(line)
            if json_err then
                debug.log("JSON error response: " .. json_err)
                done_called = true
                vim.schedule(function()
                    on_error(json_err)
                end)
                return
            end

            local event = parse_sse(line)
            if not event then
                return
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
                done_called = true
                vim.schedule(function()
                    on_done()
                end)
            elseif event.type == "error" then
                local msg = event.error and event.error.message or "Unknown API error"
                debug.log("API error: " .. msg)
                done_called = true
                vim.schedule(function()
                    on_error(msg)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            debug.log("curl exited with code: " .. exit_code)
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
    })

    if not cancel then
        debug.log("jobstart FAILED")
        on_error("Failed to start curl (is curl installed?)")
        return nil
    end

    return cancel
end

-- ============================================================
-- Provider: Anthropic API for inline editing (no tools, specialized prompt)
-- ============================================================

local inline_system_prompt = [[You are an inline code editor. Your ENTIRE response will be inserted directly into the user's source file, character for character.

You will receive: surrounding context lines (read-only), the editable region to replace, and the user's instruction.

CRITICAL - YOUR OUTPUT FORMAT:
- RAW CODE ONLY. No markdown. No code fences. No backticks. No explanations.
- Do NOT start with ``` or ```lua or ```python or any fence
- Do NOT end with ```
- Do NOT wrap anything in backticks of any kind
- Just output the replacement code directly, starting with the first character of code

WRONG (do not do this):
```lua
local x = 1
```

CORRECT (do this):
local x = 1

OTHER RULES:
- Match indentation from the surrounding context lines
- An empty editable region means "insert code here"
- The before/after context is read-only - don't include it in output]]

--- @param selected_text string The highlighted code region
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context
--- @param history table|nil Optional conversation history
--- @param lines_before string|nil Lines before the selection for context
--- @param lines_after string|nil Lines after the selection for context
--- @param indent string|nil Detected indentation to use
--- @param on_delta fun(text: string) Called with each text chunk
--- @param on_done fun() Called when complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel
local function stream_inline_anthropic(selected_text, instruction, context, history, lines_before, lines_after, indent, on_delta, on_done, on_error)
    debug.log("using anthropic provider for inline edit")

    local api_key = get_api_key()
    if not api_key then
        debug.log("API key not found!")
        on_error("API key not found")
        return nil
    end

    local user_content = ""

    if indent and indent ~= "" then
        user_content = user_content .. "## Required Indentation\nEach line of your output MUST start with exactly: \"" .. indent .. "\" (the same whitespace as surrounding code)\n\n"
    end

    if lines_before and lines_before ~= "" then
        user_content = user_content .. "## Lines Before (read-only context)\n```\n" .. lines_before .. "\n```\n\n"
    end

    user_content = user_content .. "## Highlighted Code (editable region)\n```\n" .. selected_text .. "\n```\n\n"

    if lines_after and lines_after ~= "" then
        user_content = user_content .. "## Lines After (read-only context)\n```\n" .. lines_after .. "\n```\n\n"
    end

    user_content = user_content .. "## Instruction\n" .. instruction

    if context then
        user_content = user_content .. "\n\n## Context (other open files)\n" .. context
    end

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
    })

    debug.log("Inline request body length: " .. #body)

    local tmp, err = job.write_temp(body)
    if not tmp then
        debug.log("Failed to create temp file")
        on_error(err)
        return nil
    end

    local done_called = false

    local cancel = job.run({
        cmd = job.curl_cmd({
            endpoint = config.endpoint,
            api_key = api_key,
            api_version = config.api_version,
            body_file = tmp,
        }),
        temp_file = tmp,
        on_stdout = function(line)
            -- Check for plain JSON error response (HTTP-level errors like 400, 401, 429)
            local json_err = parse_json_error(line)
            if json_err then
                debug.log("Inline JSON error response: " .. json_err)
                done_called = true
                vim.schedule(function()
                    on_error(json_err)
                end)
                return
            end

            local event = parse_sse(line)
            if not event then
                return
            end

            if event.type == "content_block_delta" then
                local delta = event.delta
                if delta and delta.type == "text_delta" and delta.text then
                    vim.schedule(function()
                        on_delta(delta.text)
                    end)
                end
            elseif event.type == "message_stop" then
                done_called = true
                vim.schedule(function()
                    on_done()
                end)
            elseif event.type == "error" then
                local msg = event.error and event.error.message or "Unknown API error"
                done_called = true
                vim.schedule(function()
                    on_error(msg)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            debug.log("inline curl exited with code: " .. exit_code)
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
    })

    if not cancel then
        on_error("Failed to start curl")
        return nil
    end

    return cancel
end

--- Build an inline prompt for opencode
local function build_inline_opencode_prompt(selected_text, instruction, context, history, lines_before, lines_after, indent)
    local parts = {
        "You are an inline code editor. Your ENTIRE response will be inserted directly into a source file.",
        "",
        "CRITICAL OUTPUT FORMAT:",
        "- RAW CODE ONLY. No markdown. No code fences. No backticks.",
        "- Do NOT start with ``` or ```lua or any fence",
        "- Do NOT end with ```",
        "- Just output the replacement code directly",
        "",
        "WRONG: ```lua\\nlocal x = 1\\n```",
        "CORRECT: local x = 1",
    }

    if indent and indent ~= "" then
        table.insert(parts, "")
        table.insert(parts, "## Required Indentation")
        table.insert(parts, "Each line MUST start with exactly: \"" .. indent .. "\"")
    end

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

    if lines_before and lines_before ~= "" then
        table.insert(parts, "")
        table.insert(parts, "## Lines Before (read-only context)")
        table.insert(parts, "```")
        table.insert(parts, lines_before)
        table.insert(parts, "```")
    end

    table.insert(parts, "")
    table.insert(parts, "## Highlighted Code (editable region)")
    table.insert(parts, "```")
    table.insert(parts, selected_text)
    table.insert(parts, "```")

    if lines_after and lines_after ~= "" then
        table.insert(parts, "")
        table.insert(parts, "## Lines After (read-only context)")
        table.insert(parts, "```")
        table.insert(parts, lines_after)
        table.insert(parts, "```")
    end

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
--- @param lines_before string|nil
--- @param lines_after string|nil
--- @param indent string|nil
--- @param on_delta fun(text: string)
--- @param on_done fun()
--- @param on_error fun(err: string)
--- @return fun()|nil cancel
local function stream_inline_opencode(selected_text, instruction, context, history, lines_before, lines_after, indent, on_delta, on_done, on_error)
    debug.log("using opencode provider for inline edit")

    local prompt = build_inline_opencode_prompt(selected_text, instruction, context, history, lines_before, lines_after, indent)
    debug.log("inline opencode prompt length: " .. #prompt)

    local tmp, err = job.write_temp(prompt)
    if not tmp then
        on_error(err)
        return nil
    end

    local done_called = false

    local cancel = job.run({
        cmd = job.pipe_cmd(tmp, opencode_cli_name .. " run --format json --title nvim-ai-inline"),
        temp_file = tmp,
        on_stdout = function(line)
            local ok, event = pcall(vim.fn.json_decode, line)
            if not ok then
                return
            end

            if event.type == "text" and event.part and event.part.text then
                vim.schedule(function()
                    on_delta(event.part.text)
                end)
            elseif event.type == "step_finish" then
                local reason = event.part and event.part.reason or "unknown"
                if reason == "stop" then
                    done_called = true
                    vim.schedule(function()
                        on_done()
                    end)
                end
            elseif event.type == "error" then
                local msg = event.part and event.part.message or event.message or "Unknown error"
                debug.log("opencode inline error: " .. msg)
                done_called = true
                vim.schedule(function()
                    on_error(msg)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    on_error("opencode exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
    })

    if not cancel then
        on_error("Failed to start opencode")
        return nil
    end

    return cancel
end

-- ============================================================
-- Public API
-- ============================================================

--- Send a streaming inline edit request to the active provider
--- @param selected_text string The highlighted code region
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context
--- @param history table|nil Optional conversation history
--- @param lines_before string|nil Lines before the selection for context
--- @param lines_after string|nil Lines after the selection for context
--- @param indent string|nil Detected indentation to use
--- @param on_delta fun(text: string) Called with each text chunk
--- @param on_done fun() Called when complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel
function M.inline_stream(selected_text, instruction, context, history, lines_before, lines_after, indent, on_delta, on_done, on_error)
    debug.log("inline_stream() called")
    debug.log("Selected text length: " .. #selected_text)
    debug.log("Instruction: " .. instruction:sub(1, 100))
    debug.log("History length: " .. (history and #history or 0))

    if is_work_mode() then
        return stream_inline_anthropic(selected_text, instruction, context, history, lines_before, lines_after, indent, on_delta, on_done, on_error)
    else
        return stream_inline_opencode(selected_text, instruction, context, history, lines_before, lines_after, indent, on_delta, on_done, on_error)
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
