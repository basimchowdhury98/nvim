local wezterm = require("wezterm")

local config = {}
if wezterm.config_builder then config = wezterm.config_builder() end

if wezterm.target_triple == "x86_64-pc-windows-msvc" or wezterm.target_triple == "aarch64-pc-windows-msvc" then
  config.default_prog = { 'powershell.exe' }
elseif wezterm.target_triple == "x86_64-apple-darwin" or wezterm.target_triple == "aarch64-apple-darwin" then
  config.default_prog = { '/bin/zsh' }
end

config.color_scheme = "Gruvbox Material (Gogh)"
config.font = wezterm.font('JetBrains Mono', { italic = true })
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"
config.background = {
  {
    source = {
      File = wezterm.config_dir .. '/background/current.jpg',
    },
    hsb = { brightness = 0.25 },
  },
  {
    source = {
      Color = 'rgba(0, 0, 0, 0.6)',  -- overlay to improve text readability
    },
    height = '100%',
    width = '100%',
  },
}


config.leader = { key = "`", mods = "ALT", timeout_millisecionds = 2000 }
config.keys = {
    {
        mods = "LEADER",
        key = "i",
        action = wezterm.action.SpawnTab "CurrentPaneDomain"
    },
    {
        mods = "LEADER",
        key = ";",
        action = wezterm.action.CloseCurrentPane { confirm = true }
    },
    {
        mods = "LEADER",
        key = "p",
        action = wezterm.action.ActivateTabRelative(-1)
    },
    {
        mods = "LEADER",
        key = "n",
        action = wezterm.action.ActivateTabRelative(1)
    },
    {
        mods = "LEADER",
        key = "\\",
        action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" }
    },
    {
        mods = "LEADER",
        key = "-",
        action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" }
    },
    {
        mods = "LEADER",
        key = "h",
        action = wezterm.action.ActivatePaneDirection "Left"
    },
    {
        mods = "LEADER",
        key = "j",
        action = wezterm.action.ActivatePaneDirection "Down"
    },
    {
        mods = "LEADER",
        key = "k",
        action = wezterm.action.ActivatePaneDirection "Up"
    },
    {
        mods = "LEADER",
        key = "l",
        action = wezterm.action.ActivatePaneDirection "Right"
    },
    {
        mods = "LEADER",
        key = "LeftArrow",
        action = wezterm.action.AdjustPaneSize { "Left", 2 }
    },
    {
        mods = "LEADER",
        key = "RightArrow",
        action = wezterm.action.AdjustPaneSize { "Right", 2 }
    },
    {
        mods = "LEADER",
        key = "DownArrow",
        action = wezterm.action.AdjustPaneSize { "Down", 2 }
    },
    {
        mods = "LEADER",
        key = "UpArrow",
        action = wezterm.action.AdjustPaneSize { "Up", 2 }
    },
    {
        mods = "LEADER",
        key = "f",
        action = wezterm.action_callback(function (win, pane)
           local tab = win:active_tab()
           for _, p in ipairs(tab:panes()) do
            if p:pane_id() ~= pane:pane_id() then
                p:activate()
                win:perform_action(wezterm.action.CloseCurrentPane { confirm = true }, p)
            end
           end
        end)
    },
}

for i = 1, 9 do
    table.insert(config.keys, {
        key = tostring(i),
        mods = "LEADER",
        action = wezterm.action.ActivateTab(i - 1)
    })
end

config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

wezterm.on("update-right-status", function (window, _)
    local text = ""
    if window:leader_is_active() then
        text = "!!!"
    end
    window:set_left_status(wezterm.format {
        { Text = text }
    })
end)

return config
