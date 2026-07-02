-- floating-terminal.lua
-- a floating terminal that mimics telescope's ui design

local M = {}

if vim.fn.has('mac') == 1 then
    vim.opt.shell = '/bin/zsh'
    vim.opt.shellcmdflag = '-c'
    vim.opt.shellquote = ''
    vim.opt.shellxquote = ''
elseif vim.fn.has('linux') == 1 then
    vim.opt.shell = '/bin/bash'
    vim.opt.shellcmdflag = '-c'
    vim.opt.shellquote = ''
    vim.opt.shellxquote = ''
else
    vim.opt.shell = 'pwsh'
    vim.opt.shellcmdflag = '-command'
    vim.opt.shellquote = '"'
    vim.opt.shellxquote = ''
end

local state = {
    win_id = nil,
    term_index = {},
}
local proj_terms = {}
local preloaded_terms = {}

local view = require('utils.terminal.view')

local map = vim.keymap.set
local lto = 'FTerm - Open'
map('n', '<leader>to', function() M.open() end, { desc = lto })
local ltk = 'FTerm - Kill all'
map('n', '<leader>tk', function() M.kill() end, { desc = ltk })
local ltd = 'FTerm - Debug'
map('n', '<leader>td', function() M.debug() end, { desc = ltd })
local ltj = 'FTerm - Open at file directory'
map('n', '<leader>tj', function()
    local file_dir = vim.fn.expand('%:p:h')
    require('utils.terminal').open_at_path(file_dir)
end, { desc = ltj })

local function set_term_keymaps(buf_id)
    local cf = 'FTerm - Rotate next'
    map({ 't', 'n' }, '<C-f>', function() M.next() end, { buffer = buf_id, desc = cf })
    local ca = 'F- Rotate prev'
    map({ 't', 'n' }, '<C-a>', function() M.prev() end, { buffer = buf_id, desc = ca })
    local ck = 'F- Escape mode to normal'
    map('t', '<C-j>', '<C-\\><C-n>', { buffer = buf_id, desc = ck })
    local cs = 'F- Snap to split/snap back to float'
    map({ 't', 'n' }, '<C-s>', function() M.snap() end, { buffer = buf_id, desc = cs })
    local co = 'Open a new nal'
    map({ 't', 'n' }, '<C-o>', function() M.open_new_terminal() end, { buffer = buf_id, desc = co })
    local cd = 'F- Kill/Delete current nal'
    map({ 't', 'n' }, '<C-k>', function() M.delete_curr() end, { buffer = buf_id, desc = cd })
end

local function get_curr_proj()
    return vim.fn.getcwd()
end

local function window_is_open()
    return state.win_id and view.window_is_open(state.win_id)
end

local function window_is_snapped()
    if not state.win_id then
        return false
    end

    return view.window_is_snapped(state.win_id)
end

local function create_terminal_buffer(path)
    local buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_id].bufhidden = 'hide'
    vim.bo[buf_id].swapfile = false

    set_term_keymaps(buf_id)

    local term = {
        buf_id = buf_id,
    }
    vim.api.nvim_buf_call(buf_id, function()
        if path == nil then
            term.term_job_id = vim.fn.termopen(vim.o.shell)
            return
        end
        term.term_job_id = vim.fn.termopen(vim.o.shell, { cwd = path })
    end)

    return term
end

local function attach_term(term)
    local curr_proj = get_curr_proj()
    local terms = proj_terms[curr_proj]
    if terms == nil then
        terms = {}
        proj_terms[curr_proj] = terms
    end

    table.insert(terms, term)
    term.index = #terms
    state.term_index[curr_proj] = #terms
end

local function get_term_to_show()
    local curr_proj = get_curr_proj()
    local curr_term_index = state.term_index[curr_proj]
    local curr_term = proj_terms[curr_proj][curr_term_index]
    local term_pos = {
        index = curr_term_index,
        terms_count = #proj_terms[curr_proj]
    }

    return curr_term, term_pos
end

local function refresh_window()
    if not window_is_open() then
        return
    end

    local curr_term, term_pos = get_term_to_show()
    view.refresh(state.win_id, curr_term.buf_id, term_pos)
end

local function open_window()
    if window_is_open() then
        return
    end

    local curr_term, term_pos = get_term_to_show()
    state.win_id = view.open_float(curr_term.buf_id, term_pos)
end

local function close_window()
    if not window_is_open() then
        return
    end

    view.close_win(state.win_id)
    state.win_id = nil
end

local function rotate_next()
    if not window_is_open() then
        return
    end

    if next(proj_terms) == nil then
        vim.notify('No terminals spawned')
        return
    end
    local proj = get_curr_proj()

    local terms = proj_terms[proj]
    if #terms == 0 then
        vim.notify('No terminals for this project spawned')
        return
    end

    local curr_term_index = state.term_index[proj]
    local next_term = curr_term_index + 1
    if next_term > #terms then
        next_term = 1 -- wrap to start
    end

    state.term_index[proj] = next_term
    refresh_window()
end

local function rotate_prev()
    if not window_is_open() then
        return
    end

    if next(proj_terms) == nil then
        vim.notify('No terminals spawned')
        return
    end
    local proj = get_curr_proj()

    local terms = proj_terms[proj]
    if #terms == 0 then
        vim.notify('No terminals for this project spawned')
        return
    end

    local curr_term_index = state.term_index[proj]
    local prev_term = curr_term_index - 1
    if prev_term < 1 then
        prev_term = #terms -- wrap to end
    end

    state.term_index[proj] = prev_term
    refresh_window()
end

local function preload()
    local curr_proj = get_curr_proj()
    local existing = preloaded_terms[curr_proj]
    if existing ~= nil then
        return
    end

    local term = create_terminal_buffer()
    vim.api.nvim_buf_set_var(term.buf_id, 'preloaded', true)
    preloaded_terms[curr_proj] = term
end

function M.open_new_terminal()
    local curr_proj = get_curr_proj()

    local term
    if preloaded_terms[curr_proj] ~= nil then
        term = preloaded_terms[curr_proj]
        vim.api.nvim_buf_del_var(term.buf_id, 'preloaded')
        preloaded_terms[curr_proj] = nil
    else
        term = create_terminal_buffer()
    end

    attach_term(term)

    if window_is_open() then
        refresh_window()
    else
        open_window()
    end

    preload()

    return state.win_id
end

function M.setup_for_project()
    preload()
end

function M.open()
    local curr_proj = get_curr_proj()

    if window_is_open() then
        if window_is_snapped() then
            close_window()
            open_window()
        end
        return state.win_id
    end
    if state.term_index[curr_proj] == nil then
        M.open_new_terminal()
    else
        open_window()
    end
    return state.win_id
end

function M.close()
    close_window()
end

function M.delete_curr()
    local curr_proj = get_curr_proj()
    local terms = proj_terms[curr_proj]
    if terms == nil or #terms == 0 then
        return
    end

    local to_delete = state.term_index[curr_proj]
    local prev = to_delete - 1

    local deleted = table.remove(terms, state.term_index[curr_proj])
    if #terms == 0 then
        state.term_index[curr_proj] = nil
        close_window()
    end

    if #terms ~= 0 and prev < 1 then
        state.term_index[curr_proj] = #terms
        refresh_window()
        return
    end

    if prev >= 1 then
        state.term_index[curr_proj] = prev
        refresh_window()
    end

    if deleted.term_job_id then
        vim.fn.jobstop(deleted.term_job_id)
    end
    if deleted.buf_id and vim.api.nvim_buf_is_valid(deleted.buf_id) then
        vim.api.nvim_buf_delete(deleted.buf_id, { force = true })
    end
end

function M.kill()
    close_window()
    for _, terms in pairs(proj_terms) do
        for _, term in ipairs(terms) do
            if term.term_job_id then
                vim.fn.jobstop(term.term_job_id)
            end
            if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
                vim.api.nvim_buf_delete(term.buf_id, { force = true })
            end
        end
    end
    for _, term in pairs(preloaded_terms) do
        if term.term_job_id then
            vim.fn.jobstop(term.term_job_id)
        end
        if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
            vim.api.nvim_buf_delete(term.buf_id, { force = true })
        end
    end

    state.term_index = nil
    state.term_index = {}
    proj_terms = {}
    preloaded_terms = {}

    vim.notify('Killed floating terminal')
end

function M.next()
    rotate_next()
end

function M.prev()
    rotate_prev()
end

function M.debug()
    print('Proj terms: ' .. vim.inspect(proj_terms))
    print('State: ' .. vim.inspect(state))
    print('Preloaded: ' .. vim.inspect(preloaded_terms))
end

function M.open_at_path(path)
    local curr_proj = get_curr_proj()

    local normalized_path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
    local normalized_proj = vim.fs.normalize(vim.fn.fnamemodify(curr_proj, ':p'))
    if not vim.endswith(normalized_proj, '/') then
        normalized_proj = normalized_proj .. '/'
    end
    if not vim.startswith(normalized_path, normalized_proj) then
        vim.notify(
            string.format('Path "%s" is not within project "%s"', normalized_path, normalized_proj),
            vim.log.levels.WARN
        )
        return
    end

    local term = create_terminal_buffer(path)
    attach_term(term)
    open_window()

    return state.win_id
end

function M.snap()
    if not window_is_open() then
        return
    end

    if window_is_snapped() then
        close_window()
        open_window()
        return state.win_id
    end
    state.win_id = view.snap_to_vsplit(state.win_id)

    return state.win_id
end

function M.__test_set_state(pstate, pproj_terms)
    state = pstate
    proj_terms = pproj_terms
end

vim.api.nvim_create_autocmd('VimResized', {
    callback = function()
        if not window_is_open() then
            return
        end
        if window_is_snapped() then
            return
        end

        view.vim_resized(state.win_id)
    end,
})

return M
