-- debug.lua
-- Shared debug logging, toggled at runtime

local M = {}

local enabled = false

function M.toggle()
    enabled = not enabled
    vim.notify("AI: Debug mode " .. (enabled and "ON" or "OFF"))
end

function M.is_enabled()
    return enabled
end

function M.log(msg)
    if enabled then
        print("[AI DEBUG] " .. msg)
    end
end

return M
