-- providers/opencode.lua
-- OpenCode server provider: communicates with opencode serve over HTTP + SSE

local debug = require("utils.ai.debug")
local job = require("utils.ai.job")

local M = {}

M.name = "opencode"

-- Active session ID (one at a time, cleared on stop)
local session_id = nil

--- Build the base URL for the opencode server
--- @param port number
--- @return string
local function base_url(port)
    return "http://127.0.0.1:" .. port
end

--- Check if the opencode server is healthy
--- @param port number
--- @return boolean
local function is_server_healthy(port)
    local url = base_url(port) .. "/global/health"
    local cmd = { "curl", "--silent", "--max-time", "2", url }
    local body, err = job.curl_sync(cmd)
    if not body then
        debug.log("[opencode] health check failed: " .. tostring(err))
        return false
    end
    local ok, data = pcall(vim.fn.json_decode, body)
    if not ok then
        debug.log("[opencode] health check JSON decode failed: " .. tostring(data))
        return false
    end
    debug.log("[opencode] health check response: " .. vim.inspect(data))
    return data.healthy == true
end

--- Start the opencode server as a detached background process
--- @param port number
local function start_server(port)
    debug.log("[opencode] starting server on port " .. port)
    local cmd
    if vim.fn.has("win32") == 1 then
        cmd = { "opencode", "serve", "--port", tostring(port) }
    else
        cmd = { "sh", "-c", "opencode serve --port " .. port .. " &" }
    end
    vim.fn.jobstart(cmd, { detach = true })
end

--- Ensure the opencode server is running, starting it if needed
--- @param port number
--- @return boolean success
local function ensure_server(port)
    if is_server_healthy(port) then
        debug.log("[opencode] server already running on port " .. port)
        return true
    end

    start_server(port)

    -- Poll for health with back-off
    local max_attempts = 20
    for i = 1, max_attempts do
        vim.wait(500)
        if is_server_healthy(port) then
            debug.log("[opencode] server started after " .. i .. " attempts")
            return true
        end
        debug.log("[opencode] waiting for server... attempt " .. i .. "/" .. max_attempts)
    end

    debug.log("[opencode] server failed to start after " .. max_attempts .. " attempts")
    return false
end

--- Create a new session on the opencode server
--- @param port number
--- @return string|nil session_id, string|nil error
local function create_session(port)
    local url = base_url(port) .. "/session"
    local body = vim.fn.json_encode(vim.empty_dict())
    local tmp, write_err = job.write_temp(body)
    if not tmp then
        return nil, write_err
    end

    local cmd = job.json_post_cmd({ url = url, body_file = tmp })
    local resp, err = job.curl_sync(cmd)
    os.remove(tmp)

    if not resp then
        return nil, "Failed to create session: " .. tostring(err)
    end

    local ok, data = pcall(vim.fn.json_decode, resp)
    if not ok then
        return nil, "Failed to parse session response: " .. tostring(data)
    end

    debug.log("[opencode] created session: " .. vim.inspect(data))

    -- Handle error envelope: {success: false, error: [...]}
    if data.success == false then
        local msg = "Session creation failed"
        if data.error then
            msg = msg .. ": " .. vim.inspect(data.error)
        end
        return nil, msg
    end

    return data.id, nil
end

--- Ensure we have an active session, creating one if needed
--- @param port number
--- @return string|nil session_id, string|nil error
local function ensure_session(port)
    if session_id then
        debug.log("[opencode] reusing session: " .. session_id)
        return session_id, nil
    end

    local id, err = create_session(port)
    if not id then
        return nil, err
    end
    session_id = id
    return session_id, nil
end

--- Clear the active session (called on stop/reset)
function M.clear_session()
    debug.log("[opencode] clearing session: " .. tostring(session_id))
    session_id = nil
end

--- Get the current session ID (for testing/debugging)
--- @return string|nil
function M.get_session_id()
    return session_id
end

--- Set the active session ID (used when resuming a session)
--- @param id string
function M.set_session_id(id)
    session_id = id
    debug.log("[opencode] set session_id to " .. tostring(id))
end

--- List all sessions from the opencode server
--- @param port number
--- @return table[]|nil sessions, string|nil error
function M.list_sessions(port)
    if not ensure_server(port) then
        return nil, "Server not running"
    end
    local url = base_url(port) .. "/session"
    local cmd = job.json_get_cmd(url)
    local resp, err = job.curl_sync(cmd)
    if not resp then
        return nil, "Failed to list sessions: " .. tostring(err)
    end
    local ok, data = pcall(vim.fn.json_decode, resp)
    if not ok then
        return nil, "Failed to parse session list: " .. tostring(data)
    end
    debug.log("[opencode] listed " .. #data .. " sessions")
    return data, nil
end

--- Get messages for a session from the opencode server
--- @param port number
--- @param sid string session ID
--- @return table[]|nil messages, string|nil error
function M.get_messages(port, sid)
    if not ensure_server(port) then
        return nil, "Server not running"
    end
    local url = base_url(port) .. "/session/" .. sid .. "/message"
    local cmd = job.json_get_cmd(url)
    local resp, err = job.curl_sync(cmd)
    if not resp then
        return nil, "Failed to get messages: " .. tostring(err)
    end
    local ok, data = pcall(vim.fn.json_decode, resp)
    if not ok then
        return nil, "Failed to parse messages: " .. tostring(data)
    end
    debug.log("[opencode] got " .. #data .. " messages for session " .. sid)
    return data, nil
end

--- Delete a session from the opencode server
--- @param port number
--- @param sid string session ID
--- @return boolean success, string|nil error
function M.delete_session(port, sid)
    if not ensure_server(port) then
        return false, "Server not running"
    end
    local url = base_url(port) .. "/session/" .. sid
    local cmd = job.json_delete_cmd(url)
    local resp, err = job.curl_sync(cmd)
    if not resp then
        return false, "Failed to delete session: " .. tostring(err)
    end
    debug.log("[opencode] deleted session: " .. sid)
    -- If we deleted our active session, clear it
    if session_id == sid then
        session_id = nil
    end
    return true, nil
end

--- Parse an SSE data line and return the JSON payload or nil
--- @param line string
--- @return table|nil
local function parse_sse(line)
    local json_str = line:match("^data: (.+)")
    if not json_str then
        return nil
    end
    local ok, event = pcall(vim.fn.json_decode, json_str)
    if not ok then
        debug.log("[opencode] SSE JSON decode failed: " .. tostring(event))
        return nil
    end
    return event
end

--- Send a message asynchronously (fire and forget)
--- @param port number
--- @param sid string session ID
--- @param text string user message
--- @param system_prompt string|nil system prompt
--- @return boolean success, string|nil error
local function send_prompt_async(port, sid, text, system_prompt)
    local url = base_url(port) .. "/session/" .. sid .. "/prompt_async"
    local body_table = {
        parts = { { type = "text", text = text } },
    }
    if system_prompt and system_prompt ~= "" then
        body_table.system = system_prompt
    end
    local body = vim.fn.json_encode(body_table)
    debug.log("[opencode] sending prompt_async: " .. body:sub(1, 200))

    local tmp, write_err = job.write_temp(body)
    if not tmp then
        return false, write_err
    end

    local cmd = job.json_post_cmd({ url = url, body_file = tmp })
    local resp, err = job.curl_sync(cmd)
    os.remove(tmp)

    if err then
        -- prompt_async returns 204 No Content on success, so empty response is ok
        -- curl_sync returns code != 0 on actual errors
        return false, "Failed to send message: " .. tostring(err)
    end

    debug.log("[opencode] prompt_async response: " .. tostring(resp))
    return true, nil
end

--- Abort a running session
--- @param port number
--- @param sid string session ID
local function abort_session(port, sid)
    local url = base_url(port) .. "/session/" .. sid .. "/abort"
    local body = vim.fn.json_encode(vim.empty_dict())
    local tmp = job.write_temp(body)
    if not tmp then return end

    local cmd = job.json_post_cmd({ url = url, body_file = tmp })
    job.curl_sync(cmd)
    os.remove(tmp)
    debug.log("[opencode] aborted session: " .. sid)
end

--- Stream a response from the opencode server via SSE
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param config table Provider config from api.lua
--- @param callbacks table {on_delta, on_done, on_error, on_thinking, on_tool_use}
--- @return fun()|nil cancel
function M.stream(messages, config, callbacks)
    debug.log("[opencode] stream() called with " .. #messages .. " messages")

    local port = config.port or 42069

    -- Ensure server is running
    if not ensure_server(port) then
        callbacks.on_error("Failed to start opencode server on port " .. port)
        return nil
    end

    -- Ensure we have a session
    local sid, session_err = ensure_session(port)
    if not sid then
        callbacks.on_error(session_err or "Failed to create session")
        return nil
    end

    -- Extract the last user message to send
    local last_user_msg = nil
    for i = #messages, 1, -1 do
        if messages[i].role == "user" then
            last_user_msg = messages[i].content
            break
        end
    end
    if not last_user_msg then
        callbacks.on_error("No user message found")
        return nil
    end

    debug.log("[opencode] sending to session " .. sid .. ": " .. last_user_msg:sub(1, 100))

    local done_called = false
    local event_count = 0
    local last_event_time = vim.uv.hrtime()
    local start_time = last_event_time
    local token_metadata = nil
    local active_part_type = "text"
    local in_think_tag = false

    local function log_timing(label)
        local now = vim.uv.hrtime()
        local since_last = (now - last_event_time) / 1e6
        local since_start = (now - start_time) / 1e6
        debug.log(string.format("[opencode] %s (event #%d, +%.0fms, total %.0fms)",
            label, event_count, since_last, since_start))
        last_event_time = now
    end

    -- Start listening to SSE event stream
    local sse_url = base_url(port) .. "/event"
    local cancel_sse
    cancel_sse = job.run({
        cmd = job.sse_curl_cmd(sse_url),
        on_stdout = function(line)
            local event = parse_sse(line)
            if not event then
                return
            end

            -- Filter events for our session
            local event_type = event.type
            local props = event.properties
            if not props then
                debug.log("[opencode] SSE event without properties: " .. tostring(event_type))
                return
            end

            -- session.idle — response complete
            if event_type == "session.idle" then
                if props.sessionID == sid then
                    event_count = event_count + 1
                    log_timing("session.idle")
                    done_called = true
                    vim.schedule(function()
                        callbacks.on_done(token_metadata)
                        -- Kill SSE connection — we're done with this request
                        if cancel_sse then
                            cancel_sse()
                        end
                    end)
                end
                return
            end

            -- session.error — session-level error
            if event_type == "session.error" then
                if props.sessionID == sid then
                    event_count = event_count + 1
                    local msg = props.error or "Unknown session error"
                    log_timing("session.error: " .. tostring(msg))
                    done_called = true
                    vim.schedule(function()
                        callbacks.on_error(tostring(msg))
                        if cancel_sse then
                            cancel_sse()
                        end
                    end)
                end
                return
            end

            -- message.part.delta — incremental text/reasoning content
            -- Structure: {delta, field, messageID, partID, sessionID}
            if event_type == "message.part.delta" then
                if props.sessionID ~= sid then
                    return
                end
                local delta = props.delta
                if not delta or delta == "" then
                    return
                end

                event_count = event_count + 1

                -- Use the delta's own field property as the authoritative source
                -- for whether this is reasoning or text. Fall back to in_think_tag
                -- for models that embed <think> tags inside text streams.
                local is_reasoning = props.field == "reasoning"
                    or (props.field ~= "text" and (active_part_type == "reasoning" or in_think_tag))
                if is_reasoning then
                    -- Handle </think> tag appearing inside thinking stream
                    local close_pos = delta:find("</think>")
                    if close_pos then
                        local before = delta:sub(1, close_pos - 1)
                        local after = delta:sub(close_pos + 8) -- len("</think>") == 8
                        in_think_tag = false
                        if before ~= "" and callbacks.on_thinking then
                            log_timing("reasoning delta")
                            vim.schedule(function()
                                callbacks.on_thinking(before)
                            end)
                        end
                        if after ~= "" then
                            local after_trimmed = after:match("^%s*(.-)%s*$")
                            if after_trimmed ~= "" then
                                log_timing("text delta")
                                vim.schedule(function()
                                    callbacks.on_delta(after_trimmed)
                                end)
                            end
                        end
                    else
                        log_timing("reasoning delta")
                        if callbacks.on_thinking then
                            vim.schedule(function()
                                callbacks.on_thinking(delta)
                            end)
                        end
                    end
                else
                    -- Handle <think> tag appearing in text stream
                    local open_pos = delta:find("<think>")
                    if open_pos then
                        local before = delta:sub(1, open_pos - 1)
                        local after = delta:sub(open_pos + 7) -- len("<think>") == 7
                        in_think_tag = true
                        if before ~= "" then
                            log_timing("text delta")
                            vim.schedule(function()
                                callbacks.on_delta(before)
                            end)
                        end
                        if after ~= "" and callbacks.on_thinking then
                            log_timing("reasoning delta")
                            vim.schedule(function()
                                callbacks.on_thinking(after)
                            end)
                        end
                    else
                        log_timing("text delta")
                        vim.schedule(function()
                            callbacks.on_delta(delta)
                        end)
                    end
                end
                return
            end

            -- message.part.updated — part metadata and tool use results
            if event_type == "message.part.updated" then
                local part = props.part
                if not part then
                    return
                end
                local event_sid = part.sessionID or props.sessionID
                if event_sid ~= sid then
                    return
                end

                event_count = event_count + 1
                local part_type = part.type

                -- Track current part type so delta events know context
                if part_type == "text" or part_type == "reasoning" or part_type == "step-start" then
                    active_part_type = part_type
                end

                if part_type == "tool" then
                    local tool_state = part.state
                    if tool_state and tool_state.status == "completed" and callbacks.on_tool_use then
                        log_timing("tool_use: " .. tostring(part.tool))
                        local tool_info = {
                            tool = part.tool or "unknown",
                            status = tool_state.status,
                            input = tool_state.input or {},
                            output = tool_state.output or nil,
                            title = tool_state.title or nil,
                        }
                        vim.schedule(function()
                            callbacks.on_tool_use(tool_info)
                        end)
                    else
                        log_timing("tool " .. tostring(part.tool) .. " status=" .. tostring(tool_state and tool_state.status))
                    end

                elseif part_type == "step-finish" then
                    log_timing("step-finish")
                    if part.tokens then
                        token_metadata = {
                            tokens = {
                                input = part.tokens.input or 0,
                                output = part.tokens.output or 0,
                                cache_read = part.tokens.cache and part.tokens.cache.read or 0,
                                cache_write = part.tokens.cache and part.tokens.cache.write or 0,
                            },
                        }
                        if part.cost then
                            token_metadata.cost = part.cost
                        end
                    end

                else
                    log_timing("part type: " .. tostring(part_type))
                end
                return
            end

            -- Log other event types we don't handle
            debug.log("[opencode] unhandled SSE event: " .. tostring(event_type))
        end,
        on_exit = function(exit_code, stderr_msg)
            local now = vim.uv.hrtime()
            local total = (now - start_time) / 1e6
            debug.log(string.format(
                "[opencode] SSE process exited: code=%d, events=%d, total=%.0fms, done_called=%s",
                exit_code, event_count, total, tostring(done_called)))
            if stderr_msg ~= "" then
                debug.log("[opencode] SSE stderr: " .. stderr_msg)
            end
            -- Don't call on_done/on_error here — SSE exit is expected when we cancel
        end,
    })

    if not cancel_sse then
        callbacks.on_error("Failed to start SSE listener (is curl installed?)")
        return nil
    end

    -- Now send the message asynchronously
    local send_ok, send_err = send_prompt_async(port, sid, last_user_msg, config.system_prompt)
    if not send_ok then
        cancel_sse()
        callbacks.on_error(send_err or "Failed to send message")
        return nil
    end

    -- Return cancel function
    return function()
        if not done_called then
            cancel_sse()
            abort_session(port, sid)
        end
    end
end

return M
