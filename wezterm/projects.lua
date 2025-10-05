local wezterm = require("wezterm")
local M = {}

local projects = {}
local nvim_path = os.getenv('NVIM')
if nvim_path then
    table.insert(projects, { label = nvim_path })
end

local function get_project_dirs()
    return {
        wezterm.home_dir .. '/Projects'
    }
end

function M.pick_projects()
    for _, dir in ipairs(get_project_dirs()) do
        local projDirs = wezterm.glob(dir .. '/*')
        for _, project in ipairs(projDirs) do
            table.insert(projects, { label = project })
        end
    end

    return wezterm.action.InputSelector {
        title = 'Projects',
        choices = projects,
        fuzzy = true,
        action = wezterm.action_callback(function(child_window, child_pane, _, label)
            if not label then return end

            -- Check if Windows (PowerShell) or Unix (bash/zsh)
            if wezterm.target_triple:find("windows") then
                child_pane:send_text('cd "' .. label .. '"; if ($?) { nvim . }\r')
            else
                child_pane:send_text('cd "' .. label .. '" && nvim .\n')
            end
        end)
    }
end

return M
