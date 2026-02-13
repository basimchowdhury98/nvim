-- debug.lua
-- Automatic logging to daily log files

local M = {}

-- Custom log directory (nil = use default)
local custom_log_dir = nil

--- Set a custom log directory (for testing)
--- @param dir string|nil
function M.set_log_dir(dir)
    custom_log_dir = dir
end

--- Get the directory where log files are stored
--- @return string
function M.get_log_dir()
    if custom_log_dir then
        return custom_log_dir
    end
    return vim.fn.stdpath("log") .. "/ai"
end

--- Get the path to today's log file
--- @return string
local function get_log_path()
    local date = os.date("%Y-%m-%d")
    return M.get_log_dir() .. "/" .. date .. ".log"
end

--- Log a message to the daily log file
--- @param msg string
function M.log(msg)
    local dir = M.get_log_dir()
    vim.fn.mkdir(dir, "p")

    local path = get_log_path()
    local timestamp = os.date("%H:%M:%S")
    local line = string.format("[%s] %s\n", timestamp, msg)

    local file = io.open(path, "a")
    if file then
        file:write(line)
        file:close()
    end
end

return M
