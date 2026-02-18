-- job.lua
-- Shared job execution utilities for AI providers

local debug = require("utils.ai.debug")

local M = {}

--- Write content to a temp file
--- @param content string
--- @return string|nil path, string|nil error
function M.write_temp(content)
    local path = vim.fn.tempname()
    local f = io.open(path, "w")
    if not f then
        return nil, "Failed to create temp file"
    end
    f:write(content)
    f:close()
    return path, nil
end

--- Run a streaming job with stdout/stderr handling
--- @param opts table {cmd: string[], on_stdout: fun(line: string), on_exit: fun(code: number, stderr: string), temp_file: string|nil}
--- @return fun()|nil cancel
function M.run(opts)
    local stderr_chunks = {}

    local job_id = vim.fn.jobstart(opts.cmd, {
        on_stdout = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    opts.on_stdout(line)
                end
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
            if opts.temp_file then
                os.remove(opts.temp_file)
            end
            opts.on_exit(exit_code, table.concat(stderr_chunks, "\n"))
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if job_id <= 0 then
        if opts.temp_file then
            os.remove(opts.temp_file)
        end
        return nil
    end

    return function()
        vim.fn.jobstop(job_id)
        if opts.temp_file then
            os.remove(opts.temp_file)
        end
    end
end

--- Build a shell command for piping temp file to a command
--- @param temp_file string
--- @param target_cmd string
--- @return string[]
function M.pipe_cmd(temp_file, target_cmd)
    if vim.fn.has("win32") == 1 then
        return { "cmd", "/c", "type " .. temp_file .. " | " .. target_cmd }
    else
        return { "sh", "-c", "cat " .. temp_file .. " | " .. target_cmd }
    end
end

--- Build a curl command for Anthropic API
--- @param opts table {endpoint: string, api_key: string, api_version: string, body_file: string}
--- @return string[]
function M.curl_cmd(opts)
    return {
        "curl", "--silent", "--no-buffer",
        "-X", "POST",
        opts.endpoint,
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. opts.api_key,
        "-H", "anthropic-version: " .. opts.api_version,
        "-d", "@" .. opts.body_file,
    }
end

--- Build a curl command for OpenAI-compatible API
--- @param opts table {endpoint: string, api_key: string, body_file: string}
--- @return string[]
function M.openai_curl_cmd(opts)
    return {
        "curl", "--silent", "--no-buffer",
        "-X", "POST",
        opts.endpoint,
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer " .. opts.api_key,
        "-d", "@" .. opts.body_file,
    }
end

return M
