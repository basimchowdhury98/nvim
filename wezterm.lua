local wezterm = require("wezterm")
local act = wezterm.action

local config = {}
if wezterm.config_builder then config = wezterm.config_builder() end

if wezterm.target_triple == "x86_64-pc-windows-msvc" or wezterm.target_triple == "aarch64-pc-windows-msvc" then
  config.default_prog = { 'powershell.exe' }
elseif wezterm.target_triple == "x86_64-apple-darwin" or wezterm.target_triple == "aarch64-apple-darwin" then
  config.default_prog = { '/bin/zsh' }
end

config.color_scheme = "Tokyo Night"
config.window_background_opacity = 0.9
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"


return config
