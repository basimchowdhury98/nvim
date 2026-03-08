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

--- Last request's token data (overwritten on each add).
--- @type table|nil
local last_request = nil

--- Recent cache hit percentages (most recent last, max 3 entries).
--- @type number[]
local cache_history = {}

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

        last_request = {
            input = metadata.tokens.input or 0,
            output = metadata.tokens.output or 0,
            cache_read = metadata.tokens.cache_read or 0,
            cache_write = metadata.tokens.cache_write or 0,
        }

        local total_in = last_request.input + last_request.cache_read + last_request.cache_write
        if last_request.cache_read > 0 and total_in > 0 then
            local pct = math.floor(last_request.cache_read / total_in * 100)
            table.insert(cache_history, pct)
            if #cache_history > 3 then
                table.remove(cache_history, 1)
            end
        end
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
    last_request = nil
    cache_history = {}
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

--- Build the stats string for display (last request's context size).
--- @return string
function M.format_stats()
    if not last_request then
        return ""
    end

    local total_in = last_request.input + last_request.cache_read + last_request.cache_write
    return format_tokens(total_in) .. "/? ctx"
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

    local label
    if lag_on then
        label = "Lag"
    elseif has_usage then
        vim.api.nvim_set_hl(0, "AILagOff", { strikethrough = true, default = true })
        label = "%#AILagOff#Lag%*"
    end

    local stats = M.format_stats()
    local parts = {}

    if stats ~= "" then
        table.insert(parts, stats)
    end

    if #cache_history > 0 then
        vim.api.nvim_set_hl(0, "AILagDim", { link = "Comment", default = true })
        local cache_parts = {}
        -- Latest first (left), oldest last (right, dimmed)
        for i = #cache_history, 1, -1 do
            local pct_str = cache_history[i] .. "%%"
            if i == #cache_history then
                -- Latest: normal text
                table.insert(cache_parts, pct_str)
            else
                -- Older: dimmed
                table.insert(cache_parts, "%#AILagDim#" .. pct_str .. "%*")
            end
        end
        table.insert(parts, table.concat(cache_parts, " "))
    end

    local content
    if #parts > 0 then
        content = " " .. label .. " | " .. table.concat(parts, " | ") .. " "
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
M._get_last_request = function() return last_request and vim.deepcopy(last_request) or nil end
M._get_cache_history = function() return vim.deepcopy(cache_history) end

return M
