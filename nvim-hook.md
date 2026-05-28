# Neovim Config Hook

Use this when you want to start Neovim with a different config name, while still loading this shared config first.

## Goal

Keep this config as the base config:

```text
~/.config/nvim
```

Create another config that loads the base config, then applies extra settings:

```text
~/.config/nvim-alt
```

## Create The Alternate Config

Create this file:

```text
~/.config/nvim-alt/init.lua
```

Use this content:

```lua
local shared_config = vim.fn.expand("~/.config/nvim")

vim.opt.runtimepath:prepend(shared_config)
vim.opt.packpath:prepend(shared_config)

dofile(shared_config .. "/init.lua")

-- Add nvim-alt-specific settings below this line.
-- Example:
-- vim.opt.relativenumber = false
```

## Start Neovim With The Alternate Config

Run:

```bash
NVIM_APPNAME=nvim-alt nvim
```

Optional shell alias:

```bash
alias nvim-alt='NVIM_APPNAME=nvim-alt nvim'
```

## Notes

`NVIM_APPNAME=nvim-alt` makes Neovim use separate paths:

```text
~/.config/nvim-alt
~/.local/share/nvim-alt
~/.local/state/nvim-alt
~/.cache/nvim-alt
```

This is useful for isolating experiments. If the shared config uses a plugin manager, plugins may be installed separately under `nvim-alt` unless the plugin manager is configured to use a shared location.

If the base config ever uses `init.vim` instead of `init.lua`, replace the `dofile(...)` line with:

```lua
vim.cmd.source(shared_config .. "/init.vim")
```
