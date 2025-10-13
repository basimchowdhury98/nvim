-- floating-terminal.lua
-- A floating terminal that mimics Telescope's UI design
-- EPIC: Multiple term tabs - when open fterm and no term, show a list of term paths (pwd always default)
-- Can save commonly used paths in list of term paths
-- When there are terms open open the last opened term and show tabs of the other terms
-- Can switch back and forth between term tabs
--
-- MVP: open new terminal instance and switch between the two (within the fterm)

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
    current_term = nil,
}

local terms = {
}

local function window_is_open()
    return state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

local function open_window()
    if window_is_open() then
        vim.api.nvim_win_set_buf(state.win_id, state.current_term.buf_id)
        return
    end

    local width = math.floor(vim.o.columns * config.width_ratio)
    local height = math.floor(vim.o.lines * config.height_ratio)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

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
    state.win_id = vim.api.nvim_open_win(state.current_term.buf_id, true, win_opts)

    -- Set window options to match Telescope using modern API
    vim.wo[state.win_id].winhighlight = 'Normal:TelescopeNormal,FloatBorder:TelescopeBorder,Title:TelescopeTitle'
end


-- Close the floating terminal
local function close_window()
    if window_is_open() then
        vim.api.nvim_win_close(state.win_id, false)
        state.win_id = nil
    end
end

local function create_terminal_buffer()
    local buf_id = vim.api.nvim_create_buf(false, true)
    -- Set buffer options using modern API
    vim.bo[buf_id].bufhidden = 'hide'
    vim.bo[buf_id].swapfile = false
    local term = {
        buf_id = buf_id
    }
    table.insert(terms, term)
    return term
end

function M.open_new_terminal()
    local term = create_terminal_buffer()
    state.current_term = term

    open_window()

    term.term_job_id = vim.fn.termopen(vim.o.shell)
end

-- Open the floating terminal
function M.open()
    if window_is_open() then
        return
    end
    if state.current_term == nil then
        M.open_new_terminal()
    else
        open_window()
    end
    vim.cmd('startinsert')
end

-- Close the floating terminal
function M.close()
    close_window()
end

function M.kill()
    close_window()
    for _, term in ipairs(terms) do
        if term.term_job_id then
            vim.fn.jobstop(term.term_job_id)
        end
        if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
            vim.api.nvim_buf_delete(term.buf_id, { force = true })
        end
    end
    state.current_term = nil
    terms = {}

    print("Killed floating terminal")
end

function M.debug()
    print("Term count: " .. #terms)
    print(vim.inspect(terms))
    print("State: " .. vim.inspect(state))
end

return M
