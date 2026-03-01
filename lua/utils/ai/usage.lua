-- usage.lua
-- Session-scoped token usage tracking and tabline display

local M = {}

local totals = {
    input = 0,
    output = 0,
    cache_read = 0,
    cache_write = 0,
    cost = 0,
    requests = 0,
}

--- Format a token count for display (e.g., 1234 -> "1.2K", 1234567 -> "1.2M")
--- @param n number
--- @return string
local function format_tokens(n)
    if n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.1fK", n / 1e3)
    end
    return tostring(n)
end

--- Accumulate usage from a request's metadata.
--- @param metadata table|nil { tokens = { input, output, cache_read, cache_write }, cost = number }
function M.add(metadata)
    if not metadata then return end
    totals.requests = totals.requests + 1
    if metadata.tokens then
        totals.input = totals.input + (metadata.tokens.input or 0)
        totals.output = totals.output + (metadata.tokens.output or 0)
        totals.cache_read = totals.cache_read + (metadata.tokens.cache_read or 0)
        totals.cache_write = totals.cache_write + (metadata.tokens.cache_write or 0)
    end
    if metadata.cost then
        totals.cost = totals.cost + metadata.cost
    end
    M.update_tabline()
end

--- Reset all usage stats.
function M.reset()
    totals.input = 0
    totals.output = 0
    totals.cache_read = 0
    totals.cache_write = 0
    totals.cost = 0
    totals.requests = 0
    M.update_tabline()
end

--- Get current totals (for testing or display).
--- @return table
function M.get_totals()
    return vim.deepcopy(totals)
end

--- Check if there is any usage data.
--- @return boolean
function M.has_data()
    return totals.requests > 0
end

--- Build the stats string for display.
--- @return string
function M.format_stats()
    if totals.requests == 0 then
        return ""
    end

    local parts = {}
    table.insert(parts, format_tokens(totals.input) .. " in")
    table.insert(parts, format_tokens(totals.output) .. " out")

    if totals.cache_read > 0 then
        table.insert(parts, format_tokens(totals.cache_read) .. " cached")
    end

    if totals.cost > 0 then
        table.insert(parts, string.format("$%.2f", totals.cost))
    end

    return table.concat(parts, " / ")
end

--- Build the full tabline string.
--- @return string
function M.build_tabline()
    local lag = require("utils.ai.lag")
    local lag_on = lag.is_running()
    local has_usage = M.has_data()

    if not lag_on and not has_usage then
        return ""
    end

    local label = lag_on and "Lag" or "AI"
    local stats = M.format_stats()

    local content
    if stats ~= "" then
        content = " " .. label .. " | " .. stats .. " "
    else
        content = " " .. label .. " "
    end

    -- Right-align using %= (everything after %= is right-aligned)
    return "%=" .. content
end

--- Update the tabline. Call after any state change.
function M.update_tabline()
    local tabline = M.build_tabline()
    if tabline == "" then
        vim.o.showtabline = 1
        vim.o.tabline = ""
    else
        vim.o.showtabline = 2
        vim.o.tabline = tabline
    end
end

-- Expose for testing
M._format_tokens = format_tokens

return M
