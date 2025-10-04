local wezterm = require("wezterm")

local config = {}
if wezterm.config_builder then config = wezterm.config_builder() end

if wezterm.target_triple == "x86_64-pc-windows-msvc" or wezterm.target_triple == "aarch64-pc-windows-msvc" then
  config.default_prog = { 'powershell.exe' }
elseif wezterm.target_triple == "x86_64-apple-darwin" or wezterm.target_triple == "aarch64-apple-darwin" then
  config.default_prog = { '/bin/zsh' }
end

config.color_scheme = "Gruvbox Material (Gogh)"
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"
config.background = {
  {
    source = {
      File = '/users/basimchowdhury/Pictures/luffy-minimal-5k-pf-2880x1800.jpg',
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



return config
