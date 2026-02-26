-- api.lua
-- AI provider: opencode CLI (default), Anthropic API (AI_WORK=true), or alt OpenAI-compatible (AI_WORK + :AIAlt)

local M = {}
local debug = require("utils.ai.debug")
local chat = require("utils.ai.chat")
local job = require("utils.ai.job")

-- Delimiters for flattened multi-turn prompts (opencode provider)
local USER_DELIM = "<|user|>"
local ASST_DELIM = "<|assistant|>"

local default_config = {
    -- Anthropic direct API settings (used when AI_WORK is set)
    api_key_env = "ANTHROPIC_API_KEY",
    model = "claude-opus-4-20250514",
    max_tokens = 4096,
    endpoint = "https://api.anthropic.com/v1/messages",
    api_version = "2023-06-01",
    system_prompt = "You are a helpful coding assistant. Be concise and direct.",
    -- Alt provider env var names (OpenAI-compatible, used when alt mode is toggled)
    alt_url_env = "AI_ALT_URL",
    alt_key_env = "AI_ALT_API_KEY",
    alt_model_env = "AI_ALT_MODEL",
}

local config = vim.deepcopy(default_config)

-- Whether the alt provider is active (only meaningful in work mode)
local alt_mode = false

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

--- Check if we should use the Anthropic API directly (work mode)
local function is_work_mode()
    local val = os.getenv("AI_WORK")
    return val and val ~= "" and val ~= "false" and val ~= "0"
end

--- Check if the alt OpenAI-compatible provider is active
local function is_alt_mode()
    return is_work_mode() and alt_mode
end

local function get_api_key()
    local key = os.getenv(config.api_key_env)
    if not key or key == "" then
        vim.notify("AI: " .. config.api_key_env .. " env var not set", vim.log.levels.ERROR)
        return nil
    end
    return key
end

local function get_alt_config()
    local url = os.getenv(config.alt_url_env)
    if not url or url == "" then
        vim.notify("AI: " .. config.alt_url_env .. " env var not set", vim.log.levels.ERROR)
        return nil
    end
    local key = os.getenv(config.alt_key_env)
    if not key or key == "" then
        vim.notify("AI: " .. config.alt_key_env .. " env var not set", vim.log.levels.ERROR)
        return nil
    end
    local model = os.getenv(config.alt_model_env)
    if not model or model == "" then
        vim.notify("AI: " .. config.alt_model_env .. " env var not set", vim.log.levels.ERROR)
        return nil
    end
    return { url = url, key = key, model = model }
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
    local parts = {
        "You are a helpful coding assistant. Be concise and direct.",
        "This conversation uses " .. USER_DELIM .. " and " .. ASST_DELIM .. " delimiters.",
        "NEVER output the " .. USER_DELIM .. " delimiter. Only output your response.",
    }
    for _, msg in ipairs(messages) do
        if msg.role == "user" then
            table.insert(parts, USER_DELIM .. "\n" .. msg.content)
        elseif msg.role == "assistant" then
            table.insert(parts, ASST_DELIM .. "\n" .. msg.content)
        end
    end
    table.insert(parts, ASST_DELIM)
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
-- Provider: Alt OpenAI-compatible API (when AI_WORK + :AIAlt)
-- ============================================================

--- Parse an SSE line from an OpenAI-compatible streaming response
--- Returns the parsed JSON object, or nil, or the string "done" for [DONE]
--- @param line string
--- @return table|string|nil
local function parse_openai_sse(line)
    local json_str = line:match("^data: (.+)")
    if not json_str then
        return nil
    end
    if json_str:match("^%[DONE%]") then
        return "done"
    end
    local ok, event = pcall(vim.fn.json_decode, json_str)
    if not ok then
        debug.log("OpenAI JSON decode failed: " .. tostring(event))
        return nil
    end
    return event
end

--- Parse a plain JSON error response from an OpenAI-compatible API
--- @param line string
--- @return string|nil error message
local function parse_openai_json_error(line)
    if line:match("^data:") or line:match("^event:") or line:match("^:") then
        return nil
    end
    local ok, obj = pcall(vim.fn.json_decode, line)
    if not ok then
        return nil
    end
    -- OpenAI error format: {"error":{"message":"...","type":"...","code":"..."}}
    if obj.error and obj.error.message then
        return obj.error.message
    end
    return nil
end

--- @param messages table[]
--- @param on_delta fun(text: string)
--- @param on_done fun()
--- @param on_error fun(err: string)
--- @return fun()|nil cancel
local function stream_alt(messages, on_delta, on_done, on_error)
    debug.log("using alt provider")

    local alt = get_alt_config()
    if not alt then
        on_error("Alt provider not configured")
        return nil
    end

    local body = vim.fn.json_encode({
        model = alt.model,
        max_tokens = config.max_tokens,
        stream = true,
        messages = vim.list_extend(
            { { role = "system", content = config.system_prompt } },
            messages
        ),
    })

    debug.log("Alt request body length: " .. #body)
    debug.log("Alt model: " .. alt.model)
    debug.log("Alt endpoint: " .. alt.url)

    local tmp, err = job.write_temp(body)
    if not tmp then
        debug.log("Failed to create temp file")
        on_error(err)
        return nil
    end

    local done_called = false

    local cancel = job.run({
        cmd = job.openai_curl_cmd({
            endpoint = alt.url,
            api_key = alt.key,
            body_file = tmp,
        }),
        temp_file = tmp,
        on_stdout = function(line)
            debug.log("alt stdout: " .. line:sub(1, 200))

            local json_err = parse_openai_json_error(line)
            if json_err then
                debug.log("Alt JSON error: " .. json_err)
                done_called = true
                vim.schedule(function()
                    on_error(json_err)
                end)
                return
            end

            local event = parse_openai_sse(line)
            if not event then
                return
            end

            if event == "done" then
                debug.log("alt stream [DONE]")
                done_called = true
                vim.schedule(function()
                    on_done()
                end)
                return
            end

            local delta = event.choices and event.choices[1] and event.choices[1].delta
            if delta and delta.content then
                vim.schedule(function()
                    on_delta(delta.content)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            debug.log("alt curl exited with code: " .. exit_code)
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            elseif not done_called then
                vim.schedule(function()
                    on_done()
                end)
            end
        end,
    })

    if not cancel then
        debug.log("alt jobstart FAILED")
        on_error("Failed to start curl (is curl installed?)")
        return nil
    end

    return cancel
end



-- ============================================================
-- Public API
-- ============================================================

--- Send a streaming request to the active provider
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param on_delta fun(text: string) Called with each text chunk as it arrives
--- @param on_done fun() Called when the response is complete
--- @param on_error fun(err: string) Called on error
--- @return fun()|nil cancel Function to cancel the request, or nil on error
function M.stream(messages, on_delta, on_done, on_error)
    debug.log("stream() called with " .. #messages .. " messages")
    debug.log("AI_WORK=" .. tostring(os.getenv("AI_WORK")))

    if is_alt_mode() then
        return stream_alt(messages, on_delta, on_done, on_error)
    elseif is_work_mode() then
        return stream_anthropic(messages, on_delta, on_done, on_error)
    else
        return stream_opencode(messages, on_delta, on_done, on_error)
    end
end

--- Toggle the alt OpenAI-compatible provider (work mode only)
--- @return boolean new alt_mode state
function M.toggle_alt()
    if not is_work_mode() then
        vim.notify("AI: Alt provider only available in work mode (AI_WORK)", vim.log.levels.WARN)
        return false
    end
    alt_mode = not alt_mode
    local provider = alt_mode and "alt" or "anthropic"
    debug.log("Toggled provider to: " .. provider)
    vim.notify("AI: Switched to " .. provider .. " provider")
    return alt_mode
end

function M.get_provider()
    if is_alt_mode() then
        return "alt"
    end
    return is_work_mode() and "anthropic" or "opencode"
end

function M.get_config()
    return vim.deepcopy(config)
end

--- Reset alt mode (for testing)
function M.reset_alt()
    alt_mode = false
end

return M
