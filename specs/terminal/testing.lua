---@diagnostic disable: duplicate-set-field
local M = {}

local eq = assert.are.same

M.term_opt_spy = {}
M.notify_spy = nil

function M.should_open_term_at(buf_id, path, message)
    assert(M.term_opt_spy[buf_id] ~= nil and M.term_opt_spy[buf_id] == path, message)
end

function M.should_find_terminal(asserts)
    local bufs = vim.api.nvim_list_bufs()

    local found = false
    for _, buf_id in ipairs(bufs) do
        if not vim.api.nvim_buf_is_valid(buf_id) then
            goto continue
        end
        if buf_id == asserts.not_including then
            goto continue
        end
        if vim.api.nvim_get_option_value("buftype", { buf = buf_id }) ~= "terminal" then
            goto continue
        end
        if asserts.preloaded and not pcall(vim.api.nvim_buf_get_var, buf_id, "preloaded") then
            goto continue
        end

        found = true
        ::continue::
    end

    if found then
        return
    end
    assert(false, "Should have found a buffer that matches asserts but didnt: " .. vim.inspect(asserts))
end

local function arrange_term(proj)
    local buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_id].bufhidden = 'hide'
    vim.bo[buf_id].swapfile = false

    local term = {
        buf_id = buf_id,
    }
    vim.api.nvim_buf_call(buf_id, function()
        term.term_job_id = vim.fn.termopen(vim.o.shell, { cwd = proj })
    end)

    return term
end

function M.arrange_terminals(sut, arrange)
    local proj_terms = {}
    if arrange.other then
        for _, proj in ipairs(arrange.other) do
            if not proj_terms[proj] then
                proj_terms[proj] = {}
            end
            local term = arrange_term(proj)
            table.insert(proj_terms[proj], term)
        end
    end

    local state = {
        win_id = nil,
        proj_current_term = {},
    }

    if not proj_terms[arrange.opened.proj] then
        proj_terms[arrange.opened.proj] = {}
    end
    local open_term = arrange_term(arrange.opened.proj)
    table.insert(proj_terms[arrange.opened.proj], open_term)
    if arrange.opened.win == 'floating' then
        local win_opts = {
            relative = 'editor',
            width = 1,
            height = 1,
            row = 1,
            col = 1,
            style = 'minimal',
            title_pos = 'center',
            title = "test"
        }
        local win_id = vim.api.nvim_open_win(open_term.buf_id, true, win_opts)
        state = {
            win_id = win_id,
        }
    end
    if arrange.opened.win == 'snapped' then
        local orig_win = vim.api.nvim_get_current_win()
        vim.cmd('botright vsplit')
        local split_win_id = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(split_win_id, open_term.buf_id)
        vim.api.nvim_set_current_win(orig_win)

        state = {
            win_id = split_win_id,
        }
    end
	state.proj_current_term = { [arrange.opened.proj] = open_term }

    sut.__test_set_state(state, proj_terms)
    return { buf_id = open_term.buf_id, win_id = state.win_id }
end

function M.find_term_buffer(term_buf_to_ignore)
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        if term_buf_to_ignore ~= nil and buf == term_buf_to_ignore then
            goto continue
        end
        if vim.api.nvim_buf_is_valid(buf) then
            local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
            if buftype == "terminal" then
                local term_job_id = vim.b[buf].terminal_job_id
                if term_job_id ~= nil and term_job_id > 0 then
                    return buf
                end
            end
        end
        ::continue::
    end
    return nil
end

function M.setup_path(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, "p")
    end
end

function M.reset()
    local wins = vim.api.nvim_list_wins()
    local current_win = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(current_win) then
        current_win = wins[1]
    end
    for _, win in ipairs(wins) do
        if win ~= current_win and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end

    for buf in pairs(M.term_opt_spy) do
        M.term_opt_spy[buf] = nil
    end
    M.notify_spy = nil
end

function M.assert_terminal_opened(win_id, expected_win_count)
    expected_win_count = expected_win_count or 2
    assert(win_id ~= nil, "Terminal window should have been returned a win id")
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    assert(buf_id ~= nil, "Terminal window should have a buffer")
    local win_count_after = #vim.api.nvim_list_wins()
    eq(win_count_after, expected_win_count, "One new window should be open after")
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf_id })
    eq(buftype, "terminal", "Buffer should be a terminal")
    local term_job_id = vim.b[buf_id].terminal_job_id
    assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")

    local config = vim.api.nvim_win_get_config(win_id)
    return buf_id, config
end

function M.assert_terminal_opened_floating(win_id, expected_win_count)
    local buf_id, config = M.assert_terminal_opened(win_id, expected_win_count)
    eq(config.relative, "editor", "Should open in a floating window")

    return buf_id
end

function M.assert_terminal_opened_snapped(win_id, expected_win_count)
    local buf_id, config = M.assert_terminal_opened(win_id, expected_win_count)
    eq(config.relative, "", "Should open in a snapped window(vsplit botright)")
    local mode = vim.api.nvim_get_mode().mode
    assert(mode == "n" or mode == "nt", "Snapped window should be in normal mode, got: " .. mode)

    return buf_id
end

function M.assert_another_preloaded_ignoring(term_buf_to_skip)
    local preloaded_next_term = M.find_term_buffer(term_buf_to_skip)
    assert(
        preloaded_next_term ~= nil and preloaded_next_term ~= term_buf_to_skip,
        "Didnt preload another term after done"
    )
end

function M.spy_on_term_open()
    local orig = vim.fn.termopen
    vim.fn.termopen = function(_, opt)
        local curr_buf = vim.api.nvim_get_current_buf()
        if opt == nil then
            orig(_)
            M.term_opt_spy[curr_buf] = "proj_path"
        else
            orig(_, opt)
            M.term_opt_spy[curr_buf] = opt.cwd
        end
    end
end

function M.spy_on_notify()
    vim.notify = function(msg, _)
        M.notify_spy = msg
    end
end

return M
