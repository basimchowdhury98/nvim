-- providers/anthropic.lua
-- Anthropic API provider: direct curl to the Anthropic Messages API

local debug = require("utils.ai.debug")
local job = require("utils.ai.job")

local M = {}

M.name = "anthropic"

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
    if line:match("^data:") or line:match("^event:") or line:match("^:") then
        return nil
    end
    local ok, obj = pcall(vim.fn.json_decode, line)
    if not ok then
        return nil
    end
    if obj.type == "error" and obj.error and obj.error.message then
        return obj.error.message
    end
    return nil
end

--- Stream a response from the Anthropic Messages API
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param config table Provider config from api.lua
--- @param callbacks table {on_delta: fun(text), on_done: fun(), on_error: fun(err)}
--- @return fun()|nil cancel
function M.stream(messages, config, callbacks)
    debug.log("using anthropic provider")

    local api_key = config.api_key
    if not api_key then
        debug.log("API key not found!")
        callbacks.on_error("API key not found")
        return nil
    end
    debug.log("API key found (length: " .. #api_key .. ")")

    local body = vim.fn.json_encode({
        model = config.model,
        max_tokens = config.max_tokens,
        system = config.system_prompt,
        stream = true,
        messages = messages,
    })

    debug.log("Request body length: " .. #body)
    debug.log("Model: " .. config.model)
    debug.log("Endpoint: " .. config.endpoint)

    local tmp, err = job.write_temp(body)
    if not tmp then
        debug.log("Failed to create temp file")
        callbacks.on_error(err)
        return nil
    end
    debug.log("Wrote request body to: " .. tmp)

    local done_called = false
    local event_count = 0
    local last_event_time = vim.uv.hrtime()
    local start_time = last_event_time
    local usage_data = { input = 0, output = 0, cache_read = 0, cache_write = 0 }

    local function log_timing(label)
        local now = vim.uv.hrtime()
        local since_last = (now - last_event_time) / 1e6
        local since_start = (now - start_time) / 1e6
        debug.log(string.format("[anthropic] %s (event #%d, +%.0fms, total %.0fms)",
            label, event_count, since_last, since_start))
        last_event_time = now
    end

    local cancel = job.run({
        cmd = job.curl_cmd({
            endpoint = config.endpoint,
            api_key = api_key,
            api_version = config.api_version,
            body_file = tmp,
        }),
        temp_file = tmp,
        on_stdout = function(line)
            event_count = event_count + 1
            debug.log("stdout line: " .. line:sub(1, 200))

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

            log_timing("event: " .. tostring(event.type))

            if event.type == "message_start" then
                local msg = event.message
                if msg and msg.usage then
                    usage_data.input = msg.usage.input_tokens or 0
                    usage_data.cache_read = msg.usage.cache_read_input_tokens or 0
                    usage_data.cache_write = msg.usage.cache_creation_input_tokens or 0
                end
            elseif event.type == "message_delta" then
                if event.usage then
                    usage_data.output = event.usage.output_tokens or 0
                end
            elseif event.type == "content_block_delta" then
                local delta = event.delta
                if delta and delta.type == "text_delta" and delta.text then
                    vim.schedule(function()
                        callbacks.on_delta(delta.text)
                    end)
                end
            elseif event.type == "message_stop" then
                log_timing("message_stop")
                done_called = true
                vim.schedule(function()
                    callbacks.on_done({ tokens = usage_data })
                end)
            elseif event.type == "error" then
                local msg = event.error and event.error.message or "Unknown API error"
                log_timing("error: " .. msg)
                done_called = true
                vim.schedule(function()
                    callbacks.on_error(msg)
                end)
            end
        end,
        on_exit = function(exit_code, stderr_msg)
            local now = vim.uv.hrtime()
            local total = (now - start_time) / 1e6
            debug.log(string.format(
                "[anthropic] process exited: code=%d, events=%d, total=%.0fms, done_called=%s",
                exit_code, event_count, total, tostring(done_called)))
            if stderr_msg ~= "" then
                debug.log("[anthropic] stderr: " .. stderr_msg)
            end
            if exit_code ~= 0 and not done_called then
                vim.schedule(function()
                    callbacks.on_error("curl exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            end
        end,
    })

    if not cancel then
        debug.log("jobstart FAILED")
        callbacks.on_error("Failed to start curl (is curl installed?)")
        return nil
    end

    return cancel
end

return M
