-- spinner.lua
-- Shared spinner animation for chat and inline editing

local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local INTERVAL_MS = 80

--- Create a new spinner instance
--- @param opts table {on_frame: fun(frame: string, index: number)}
--- @return table {start: fun(), stop: fun(), is_running: fun(): boolean}
function M.create(opts)
    local timer = nil
    local frame_index = 1

    local function stop()
        if timer then
            timer:stop()
            timer:close()
            timer = nil
        end
        frame_index = 1
    end

    local function start()
        if timer then
            return
        end

        frame_index = 1
        opts.on_frame(FRAMES[1], 1)

        timer = vim.uv.new_timer()
        timer:start(INTERVAL_MS, INTERVAL_MS, vim.schedule_wrap(function()
            frame_index = (frame_index % #FRAMES) + 1
            opts.on_frame(FRAMES[frame_index], frame_index)
        end))
    end

    local function is_running()
        return timer ~= nil
    end

    return {
        start = start,
        stop = stop,
        is_running = is_running,
    }
end

return M
