-- providers/alt.lua
-- Alt provider: OpenAI-compatible API (used when AI_WORK + :AIAlt)

local debug = require("utils.ai.debug")
local job = require("utils.ai.job")

local M = {}

M.name = "alt"

--- Parse an SSE line from an OpenAI-compatible streaming response
--- Returns the parsed JSON object, or nil, or the string "done" for [DONE]
--- @param line string
--- @return table|string|nil
local function parse_sse(line)
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
--- Handles standard OpenAI format ({error: {message: ...}}) and
--- non-standard formats ({detail: ...}, {message: ...}).
--- @param line string
--- @return string|nil error message
local function parse_json_error(line)
    if line:match("^data:") or line:match("^event:") or line:match("^:") then
        return nil
    end
    local ok, obj = pcall(vim.fn.json_decode, line)
    if not ok then
        return nil
    end
    if obj.error and obj.error.message then
        return obj.error.message
    end
    if obj.error and type(obj.error) == "string" then
        return obj.error
    end
    if obj.detail and type(obj.detail) == "string" then
        return obj.detail
    end
    if obj.message and type(obj.message) == "string" and not obj.choices then
        return obj.message
    end
    return nil
end

--- Stream a response from an OpenAI-compatible API
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param config table Provider config from api.lua
--- @param callbacks table {on_delta: fun(text), on_done: fun(), on_error: fun(err)}
--- @return fun()|nil cancel
function M.stream(messages, config, callbacks)
    debug.log("using alt provider")

    if not config.endpoint or not config.api_key or not config.model then
        callbacks.on_error("Alt provider not configured")
        return nil
    end

    local body = vim.fn.json_encode({
        model = config.model,
        max_tokens = config.max_tokens,
        stream = true,
        stream_options = { include_usage = true },
        messages = vim.list_extend(
            { { role = "system", content = config.system_prompt } },
            messages
        ),
    })

    debug.log("Alt request body length: " .. #body)
    debug.log("Alt model: " .. config.model)
    debug.log("Alt endpoint: " .. config.endpoint)

    local tmp, err = job.write_temp(body)
    if not tmp then
        debug.log("Failed to create temp file")
        callbacks.on_error(err)
        return nil
    end

    local done_called = false
    local event_count = 0
    local last_event_time = vim.uv.hrtime()
    local start_time = last_event_time
    local usage_data = nil

    local function log_timing(label)
        local now = vim.uv.hrtime()
        local since_last = (now - last_event_time) / 1e6
        local since_start = (now - start_time) / 1e6
        debug.log(string.format("[alt] %s (event #%d, +%.0fms, total %.0fms)",
            label, event_count, since_last, since_start))
        last_event_time = now
    end

    local cancel = job.run({
        cmd = job.openai_curl_cmd({
            endpoint = config.endpoint,
            api_key = config.api_key,
            body_file = tmp,
        }),
        temp_file = tmp,
        on_stdout = function(line)
            event_count = event_count + 1
            debug.log("alt stdout: " .. line:sub(1, 200))

            local json_err = parse_json_error(line)
            if json_err then
                log_timing("JSON error: " .. json_err)
                done_called = true
                vim.schedule(function()
                    callbacks.on_error(json_err)
                end)
                return
            end

            local event = parse_sse(line)
            if not event then
                return
            end

            if event == "done" then
                log_timing("[DONE]")
                done_called = true
                local metadata = nil
                if usage_data then
                    metadata = { tokens = usage_data }
                end
                vim.schedule(function()
                    callbacks.on_done(metadata)
                end)
                return
            end

            log_timing("event: delta")

            if event.usage then
                usage_data = {
                    input = event.usage.prompt_tokens or 0,
                    output = event.usage.completion_tokens or 0,
                    cache_read = 0,
                    cache_write = 0,
                }
            end

            local delta = event.choices and event.choices[1] and event.choices[1].delta
            if delta and delta.content then
                vim.schedule(function()
                    callbacks.on_delta(delta.content)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            local now = vim.uv.hrtime()
            local total = (now - start_time) / 1e6
            debug.log(string.format(
                "[alt] process exited: code=%d, events=%d, total=%.0fms, done_called=%s",
                exit_code, event_count, total, tostring(done_called)))
            if stderr_msg ~= "" then
                debug.log("[alt] stderr: " .. stderr_msg)
            end
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    callbacks.on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            elseif not done_called then
                debug.log("[alt] WARNING: process exited without [DONE], calling on_done as fallback")
                vim.schedule(function()
                    callbacks.on_done(nil)
                end)
            end
        end,
    })

    if not cancel then
        debug.log("alt jobstart FAILED")
        callbacks.on_error("Failed to start curl (is curl installed?)")
        return nil
    end

    return cancel
end

return M
