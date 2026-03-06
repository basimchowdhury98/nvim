-- providers/opencode.lua
-- OpenCode CLI provider: pipes a flattened prompt to the opencode CLI

local debug = require("utils.ai.debug")
local job = require("utils.ai.job")

local M = {}

M.name = "opencode"

-- Delimiters for flattened multi-turn prompts
local USER_DELIM = "<|user|>"
local ASST_DELIM = "<|assistant|>"

local opencode_cli_name = "7619b34b-opencode-d0a72d8a"

--- Build the user prompt from conversation messages.
--- opencode run doesn't support multi-turn, so we flatten the
--- conversation into a single prompt with delimiters.
--- @param messages table[]
--- @param system_prompt string
--- @return string
function M.build_prompt(messages, system_prompt)
    local parts = {
        system_prompt,
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

--- Stream a response from the opencode CLI
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param config table Provider config from api.lua
--- @param callbacks table {on_delta: fun(text), on_done: fun(), on_error: fun(err)}
--- @return fun()|nil cancel
function M.stream(messages, config, callbacks)
    debug.log("using opencode provider")

    local prompt = M.build_prompt(messages, config.system_prompt)
    debug.log("opencode prompt length: " .. #prompt)

    local tmp, err = job.write_temp(prompt)
    if not tmp then
        callbacks.on_error(err)
        return nil
    end

    local done_called = false
    local event_count = 0
    local last_event_time = vim.uv.hrtime()
    local start_time = last_event_time

    local function log_timing(label)
        local now = vim.uv.hrtime()
        local since_last = (now - last_event_time) / 1e6 -- ms
        local since_start = (now - start_time) / 1e6
        debug.log(string.format("[opencode] %s (event #%d, +%.0fms, total %.0fms)",
            label, event_count, since_last, since_start))
        last_event_time = now
    end

    local cancel = job.run({
        cmd = job.pipe_cmd(tmp, opencode_cli_name .. " run --format json --title nvim-ai"),
        temp_file = tmp,
        on_stdout = function(line)
            event_count = event_count + 1
            debug.log("stdout line: " .. line:sub(1, 200))

            local ok, event = pcall(vim.fn.json_decode, line)
            if not ok then
                debug.log("[opencode] JSON decode failed: " .. tostring(event))
                return
            end

            log_timing("event: " .. tostring(event.type))

            if event.type == "text" and event.part and event.part.text then
                vim.schedule(function()
                    callbacks.on_delta(event.part.text)
                end)
            elseif event.type == "step_finish" then
                local reason = event.part and event.part.reason or "unknown"
                log_timing("step_finish reason=" .. reason)
                if reason == "stop" then
                    done_called = true
                    local metadata = nil
                    if event.part then
                        metadata = {}
                        if event.part.tokens then
                            metadata.tokens = {
                                input = event.part.tokens.input or 0,
                                output = event.part.tokens.output or 0,
                                cache_read = event.part.tokens.cache and event.part.tokens.cache.read or 0,
                                cache_write = event.part.tokens.cache and event.part.tokens.cache.write or 0,
                            }
                        end
                        if event.part.cost then
                            metadata.cost = event.part.cost
                        end
                    end
                    vim.schedule(function()
                        callbacks.on_done(metadata)
                    end)
                end
            elseif event.type == "error" then
                local msg = event.part and event.part.message or event.message or "Unknown error"
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
                "[opencode] process exited: code=%d, events=%d, total=%.0fms, done_called=%s",
                exit_code, event_count, total, tostring(done_called)))
            if stderr_msg ~= "" then
                debug.log("[opencode] stderr: " .. stderr_msg)
            end
            if done_called then
                return
            end
            if event_count == 0 and exit_code ~= 0 then
                debug.log("[opencode] no events received, treating as error")
                vim.schedule(function()
                    callbacks.on_error("opencode exited with code " .. exit_code .. ": " .. stderr_msg)
                end)
            elseif not done_called then
                debug.log("[opencode] WARNING: process exited without step_finish, calling on_done as fallback")
                vim.schedule(function()
                    callbacks.on_done(nil)
                end)
            end
        end,
    })

    if not cancel then
        callbacks.on_error("Failed to start opencode (is it installed?)")
        return nil
    end

    return cancel
end

return M
