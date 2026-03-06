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

--- Format a state snapshot into a human-readable dump string.
--- @param snapshot table from init.build_state_snapshot()
--- @return string
function M.format_snapshot(snapshot)
    local lines = {}

    local function add(text)
        table.insert(lines, text)
    end

    local function add_separator()
        add(string.rep("=", 72))
    end

    add_separator()
    add("AI CONTEXT DUMP — " .. os.date("%Y-%m-%d %H:%M:%S"))
    add_separator()

    add("")
    add("Project: " .. snapshot.project)
    add("Active: " .. tostring(snapshot.active))
    add("Provider: " .. snapshot.provider)

    -- Usage
    add("")
    add_separator()
    add("USAGE")
    add_separator()
    local u = snapshot.usage
    add("Requests: " .. u.requests)
    add("Input tokens: " .. u.input)
    add("Output tokens: " .. u.output)
    add("Cache read: " .. u.cache_read)
    add("Cache write: " .. u.cache_write)
    add("Cost: $" .. string.format("%.4f", u.cost))

    -- Project buffers
    add("")
    add_separator()
    add("PROJECT BUFFERS (" .. #snapshot.project_buffers .. ")")
    add_separator()
    if #snapshot.project_buffers == 0 then
        add("(none)")
    else
        for _, name in ipairs(snapshot.project_buffers) do
            add("  " .. name)
        end
    end

    -- Conversation history
    add("")
    add_separator()
    add("CONVERSATION (" .. #snapshot.conversation .. " messages)")
    add_separator()
    if #snapshot.conversation == 0 then
        add("(empty)")
    else
        for i, msg in ipairs(snapshot.conversation) do
            add("")
            add("[" .. i .. "] " .. msg.role .. ":")
            if msg.thinking then
                add("[thinking]")
                add(msg.thinking)
                add("[/thinking]")
            end
            add(msg.content)
        end
    end

    -- Buffer context (what gets injected into the first message)
    add("")
    add_separator()
    add("BUFFER CONTEXT BLOCK")
    add_separator()
    if snapshot.buffer_context then
        add(snapshot.buffer_context)
    else
        add("(none)")
    end

    -- Lag mode state
    add("")
    add_separator()
    add("LAG MODE")
    add_separator()
    local lag_state = snapshot.lag
    add("Running: " .. tostring(lag_state.running))
    local buf_count = 0
    for _ in pairs(lag_state.buffers) do
        buf_count = buf_count + 1
    end
    add("Tracked buffers: " .. buf_count)
    for name, bstate in pairs(lag_state.buffers) do
        add("")
        add("  Buffer: " .. name)
        add("  Baseline lines: " .. bstate.baseline_lines)
        add("  Processing: " .. tostring(bstate.processing))
        add("  Pending save: " .. tostring(bstate.pending_save))
        add("  Queue count: " .. bstate.queue_count)
        add("  Active modification: " .. tostring(bstate.active_index))
        add("  Modifications: " .. #bstate.modifications)
        for j, mod in ipairs(bstate.modifications) do
            add("    [" .. j .. "] line " .. mod.line .. " (original " .. mod.original_start .. "-" .. mod.original_end .. ")")
            add("    original: " .. table.concat(mod.original_lines, "\n    "))
            add("    new: " .. table.concat(mod.new_lines, "\n    "))
        end
    end

    add("")
    add_separator()

    return table.concat(lines, "\n") .. "\n"
end

--- Write a string to a named dump file in the log directory and open it.
--- @param content string
--- @param name string filename prefix (e.g. "chat_dump", "lag_dump")
function M.write_dump_file(content, name)
    local log_dir = M.get_log_dir()
    vim.fn.mkdir(log_dir, "p")
    local dump_path = log_dir .. "/" .. name .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"

    local f = io.open(dump_path, "w")
    if not f then
        vim.notify("AI: Failed to write dump", vim.log.levels.ERROR)
        return
    end
    f:write(content)
    f:close()

    vim.cmd("vsplit " .. vim.fn.fnameescape(dump_path))
    vim.bo.modifiable = false
    vim.bo.readonly = true
    vim.notify("AI: Dump written to " .. dump_path)
end

--- Write a formatted snapshot to a file in the log directory and open it.
--- @param snapshot table from init.build_state_snapshot()
function M.write_dump(snapshot)
    local content = M.format_snapshot(snapshot)

    local log_dir = M.get_log_dir()
    vim.fn.mkdir(log_dir, "p")
    local dump_path = log_dir .. "/context_dump_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"

    local f = io.open(dump_path, "w")
    if not f then
        vim.notify("AI: Failed to write context dump", vim.log.levels.ERROR)
        return
    end
    f:write(content)
    f:close()

    vim.cmd("vsplit " .. vim.fn.fnameescape(dump_path))
    vim.bo.modifiable = false
    vim.bo.readonly = true
    vim.notify("AI: Context dump written to " .. dump_path)
end

return M
