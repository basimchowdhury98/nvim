local wezterm = require("wezterm")
local act = wezterm.action

local config = {}
if wezterm.config_builder then config = wezterm.config_builder() end

config.default_prog = { 'powershell.exe' }
config.color_scheme = "Tokyo Night"
config.window_background_opacity = 0.9
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"


return config
