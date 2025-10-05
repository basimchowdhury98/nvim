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


config.leader = { key = "q", mods = "ALT", timeout_millisecionds = 2000 }
config.keys = {
    {
        mods = "LEADER",
        key = "c",
        action = wezterm.action.SpawnTab "CurrentPaneDomain"
    },
    {
        mods = "LEADER",
        key = "x",
        action = wezterm.action.CloseCurrentPane { confirm = true }
    }
}

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
