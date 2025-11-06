-- floating-terminal.lua
-- a floating terminal that mimics telescope's ui design
-- epic: multiple term tabs - when open fterm and no term, show a list of term paths (pwd always default)
-- can save commonly used paths in list of term paths
-- when there are terms open open the last opened term and show tabs of the other terms
-- can switch back and forth between term tabs
--
-- mvp: open new terminal instance and switch between the two (within the fterm)

local M = {}

if vim.fn.has("mac") == 1 then
    vim.opt.shell = "/bin/zsh"
    vim.opt.shellcmdflag = "-c"
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
else
    vim.opt.shell = "powershell"
    vim.opt.shellcmdflag = "-command"
    vim.opt.shellquote = "\""
    vim.opt.shellxquote = ""
end

local config = {
    width_ratio = 0.8,
    height_ratio = 0.8,
    border = 'rounded',
    title = ' Terminal ',
    prompt_title = ' Command ',
}

local state = {
    win_id = nil,
    proj_current_term = {},
}

local projTerms = {
}

local function get_curr_proj()
    return vim.fn.getcwd()
end

local function window_is_open()
    return state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

local function create_terminal_buffer()
    local buf_id = vim.api.nvim_create_buf(false, true)
    -- Set buffer options using modern API
    vim.bo[buf_id].bufhidden = 'hide'
    vim.bo[buf_id].swapfile = false

    local projPath = get_curr_proj()

    local terms = projTerms[projPath]
    if terms == nil then
        terms = {}
        projTerms[projPath] = terms
    end
    local term = {
        buf_id = buf_id
    }
    table.insert(terms, term)
    return term
end

local function refresh_window()
    local curr_proj = get_curr_proj();

    if window_is_open() then
        if state.proj_current_term[curr_proj] == nil then
            local term = create_terminal_buffer()
            term.term_job_id = vim.fn.termopen(vim.o.shell)
            state.proj_current_term[curr_proj] = term
        end

        vim.api.nvim_win_set_buf(state.win_id, state.proj_current_term[curr_proj].buf_id)
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
    state.win_id = vim.api.nvim_open_win(state.proj_current_term[curr_proj].buf_id, true, win_opts)

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

function M.open_new_terminal()
    local curr_proj = get_curr_proj();

    local term = create_terminal_buffer()
    state.proj_current_term[curr_proj] = term

    refresh_window()

    term.term_job_id = vim.fn.termopen(vim.o.shell)
    vim.cmd('startinsert')
end

-- Open the floating terminal
function M.open()
    local curr_proj = get_curr_proj();

    if window_is_open() then
        return state.win_id
    end
    if state.proj_current_term[curr_proj] == nil then
        M.open_new_terminal()
    else
        refresh_window()
    end
    vim.cmd('startinsert')
    return state.win_id
end

-- Close the floating terminal
function M.close()
    close_window()
end

function M.kill()
    close_window()
    for _, terms in pairs(projTerms) do
        for _, term in ipairs(terms) do
            if term.term_job_id then
                vim.fn.jobstop(term.term_job_id)
            end
            if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
                vim.api.nvim_buf_delete(term.buf_id, { force = true })
            end
        end
    end
    state.proj_current_term = nil
    state.proj_current_term = {}
    projTerms = {}

    print("Killed floating terminal")
end

function M.next()
    if next(projTerms) == nil then
        vim.notify("No terminals spawned")
        return
    end
    local proj = get_curr_proj()

    local terms = projTerms[proj]
    if #terms == 0 then
        vim.notify("No terminals for this project spawned")
        return
    end

    local nextTerm = -1
    for index, term in ipairs(terms) do
        if index == #terms then
            nextTerm = 1
            break
        end
        if state.proj_current_term[proj].buf_id == term.buf_id then
            nextTerm = index + 1
            break
        end
    end
    state.proj_current_term[proj] = terms[nextTerm]
    refresh_window()
end

function M.prev()
    if next(projTerms) == nil then
        vim.notify("No terminals spawned")
        return
    end
    local proj = get_curr_proj()

    local terms = projTerms[proj]
    if #terms == 0 then
        vim.notify("No terminals for this project spawned")
        return
    end

    local nextTerm = -1
    for i = #terms, 1, -1 do
        if i == 1 then
            nextTerm = #terms
            break
        end
        local term = terms[i]
        if state.proj_current_term[proj].buf_id == term.buf_id then
            nextTerm = i - 1
            break
        end
    end
    state.proj_current_term[proj] = terms[nextTerm]
    refresh_window()
end

function M.debug()
    print("Proj terms: " .. vim.inspect(projTerms))
    print("State: " .. vim.inspect(state))
end

return M
