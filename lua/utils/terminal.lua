-- floating-terminal.lua
-- A floating terminal that mimics Telescope's UI design

local M = {}

-- Configuration
local config = {
  width_ratio = 0.8,
  height_ratio = 0.8,
  border = 'rounded',
  title = ' Terminal ',
  prompt_title = ' Command ',
}

-- State
local state = {
  win_id = nil,
  buf_id = nil,
  term_job_id = nil,
  is_open = false,
}

-- Create the floating window with Telescope-like styling
local function create_floating_window()
  local width = math.floor(vim.o.columns * config.width_ratio)
  local height = math.floor(vim.o.lines * config.height_ratio)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer if it doesn't exist
  if not state.buf_id or not vim.api.nvim_buf_is_valid(state.buf_id) then
    state.buf_id = vim.api.nvim_create_buf(false, true)

    -- Set buffer options using modern API
    vim.bo[state.buf_id].bufhidden = 'hide'
    vim.bo[state.buf_id].swapfile = false
  end

  -- Window options that match Telescope's style
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = config.border,
    title = config.title,
    title_pos = 'center',
  }

  -- Create the window
  state.win_id = vim.api.nvim_open_win(state.buf_id, true, win_opts)

  -- Set window options to match Telescope using modern API
  vim.wo[state.win_id].winhighlight = 'Normal:TelescopeNormal,FloatBorder:TelescopeBorder,Title:TelescopeTitle'
  vim.wo[state.win_id].winblend = 10

  -- Start terminal if not already running (this sets buftype automatically)
  if not state.term_job_id then
    state.term_job_id = vim.fn.termopen(vim.o.shell)
  end

  state.is_open = true
end

-- Close the floating terminal
local function close_terminal()
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    vim.api.nvim_win_close(state.win_id, false)
    state.win_id = nil
    state.is_open = false
  end
end

-- Toggle the floating terminal
function M.toggle()
  if state.is_open and state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    close_terminal()
  else
    create_floating_window()
    -- Enter insert mode automatically
    vim.cmd('startinsert')
  end
end

-- Open the floating terminal
function M.open()
  if not state.is_open then
    create_floating_window()
    vim.cmd('startinsert')
  end
end

-- Close the floating terminal
function M.close()
  close_terminal()
end

-- Check if terminal is open
function M.is_open()
  return state.is_open and state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

-- Get terminal buffer id
function M.get_buf_id()
  return state.buf_id
end

-- Get terminal window id
function M.get_win_id()
  return state.win_id
end

function M.kill()
    close_terminal()
    if state.term_job_id then
        vim.fn.jobstop(state.term_job_id)
        state.term_job_id = nil
    end
    if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
        vim.api.nvim_buf_delete(state.buf_id, { force = true })
        state.buf_id = nil
    end

    print("Killed floating terminal")
end

return M
