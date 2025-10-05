local wezterm = require("wezterm")
local M = {}

local projects = {}
table.insert(projects, { label = os.getenv('NVIM') })

local function get_project_dirs()
    return {
        wezterm.home_dir .. '\\Projects'
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

            child_window:perform_action(wezterm.action.SwitchToWorkspace {
                name = label:match("([^/]+)$"),
                spawn = { cwd = label }
            }, child_pane)

            wezterm.log_warn('Got project: ' .. wezterm.json_encode(projects, true))
        end)
    }
end

return M
