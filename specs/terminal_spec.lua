local eq = assert.are.same
local function find_term_buffer(term_buf_to_ignore)
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        if term_buf_to_ignore ~= nil and buf == term_buf_to_ignore then
            goto continue
        end
        if vim.api.nvim_buf_is_valid(buf) then
            local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
            if buftype == 'terminal' then
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

local function setup_path(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, 'p')
    end
end

local function assert_terminal_opened(win_id)
    assert(win_id ~= nil)
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    assert(buf_id ~= nil)
    local win_count_after = #vim.api.nvim_list_wins()
    eq(win_count_after, 2, "One new window should be open after")
    local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf_id })
    eq(buftype, 'terminal', "Buffer should be a terminal")
    local config = vim.api.nvim_win_get_config(win_id)
    eq(config.title[1][1], ' Terminal ', "Should have correct title")
    local term_job_id = vim.b[buf_id].terminal_job_id
    assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")

    return buf_id
end

local function assert_another_preloaded_ignoring(term_buf_to_skip)
    local preloaded_next_term = find_term_buffer(term_buf_to_skip)
    assert(preloaded_next_term ~= nil and preloaded_next_term ~= term_buf_to_skip,
        "Didnt preload another term after done")
end

local term_opt_spy = {}
local function spyOnTermOpen()
    local orig = vim.fn.termopen
    vim.fn.termopen = function(_, opt)
        local curr_buf = vim.api.nvim_get_current_buf()
        if opt == nil then
            orig(_)
            term_opt_spy[curr_buf] = "proj_path"
        else
            orig(_, opt)
            term_opt_spy[curr_buf] = opt.cwd
        end
    end
end

local notifySpy
local function spyOnNotify()
    vim.notify = function(msg, _)
        notifySpy = msg
    end
end

describe("Floating terminal", function()
    local term = require("utils.terminal")
    local test_proj = vim.fn.stdpath("cache") .. "\\terminal-test"
    local test_proj_2 = vim.fn.stdpath("cache") .. "\\terminal-test-2"
    setup_path(test_proj)
    setup_path(test_proj_2)
    spyOnTermOpen()
    spyOnNotify()

    before_each(function()
        term.kill()
        vim.fn.chdir(test_proj)
        term_opt_spy = {}
        notifySpy = nil
    end)

    it("opens the terminal without setup", function()
        local win_id = term.open()

        local buf_id = assert_terminal_opened(win_id)
        assert(term_opt_spy[buf_id] ~= nil and term_opt_spy[buf_id] == "proj_path",
            "A specific path was passed when it should be pwd/proj path")
        assert_another_preloaded_ignoring(buf_id)
    end)

    it("opens window with setup uses a preloaded term", function()
        term.setupForProject()
        local preloaded_term_buf = find_term_buffer()

        local win_id = term.open()

        local buf_id = assert_terminal_opened(win_id)
        assert(preloaded_term_buf ~= nil)
        eq(buf_id, preloaded_term_buf, "Didnt use the preloaded term")
        assert_another_preloaded_ignoring(buf_id)
    end)

    it("processes opens idempotently", function()
        local win_count_before = #vim.api.nvim_list_wins()

        local _ = term.open()
        local win_id = term.open()

        local buf_id = assert_terminal_opened(win_id)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "Only one new window should have opened")
        assert_another_preloaded_ignoring(buf_id)
    end)

    it("opens new terminal in new project", function()
        local win_id_proj1 = term.open()
        local buf_id_proj1 = assert_terminal_opened(win_id_proj1)
        term.close()
        vim.fn.chdir(test_proj_2)
        local win_id_proj2 = term.open()
        local buf_id_proj2 = assert_terminal_opened(win_id_proj2)

        assert(win_id_proj1 ~= win_id_proj2, "Same window shouldnt be used for both projects")
        assert(buf_id_proj1 ~= buf_id_proj2, "Same buffer shouldnt be used for both projects")
    end)

    it("closes the window when one is open", function()
        local win_count_before = #vim.api.nvim_list_wins()
        local win_id = term.open()

        term.close()

        assert(win_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before, "Window wasnt closed")
    end)

    it("closes window idempotently", function()
        local win_count_before = #vim.api.nvim_list_wins()
        local win_id = term.open()

        term.close()
        term.close()

        assert(win_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before, "Window wasnt closed")
    end)

    it("opens a new terminal", function()
        local win_id = term.open_new_terminal()

        local buf_id = assert_terminal_opened(win_id)
        assert_another_preloaded_ignoring(buf_id)
    end)

    it("opens new terminal with setup uses a preloaded term", function()
        term.setupForProject()
        local preloaded_term_buf = find_term_buffer()

        local win_id = term.open_new_terminal()

        local buf_id = assert_terminal_opened(win_id)
        assert(preloaded_term_buf ~= nil, "A term buffer wasnt preloaded")
        eq(buf_id, preloaded_term_buf, "Didnt use the preloaded term")
        assert_another_preloaded_ignoring(buf_id)
    end)

    it("opens 2 new terminals when_open_new terminal called twice", function()
        local win_count_before = #vim.api.nvim_list_wins()

        local win_id = term.open_new_terminal()
        local buf_id = assert_terminal_opened(win_id)
        local win_id_2 = term.open_new_terminal()

        assert(win_id == win_id_2, "Different windows were used when it should be just one")
        local buf_id_2 = assert_terminal_opened(win_id_2)
        assert(buf_id ~= buf_id_2, "Same buffer used each time but should be different")
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "More than 1 new window opened")
    end)

    it("can rotate to the prev terminal", function()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, first_buf_id, "Prev didnt go back to first term")
    end)

    it("can rotate to the last terminal if preving from first terminal", function()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev() --puts win on first term
        term.prev()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, second_buf_id, "Prev didnt wrap around to the last buffer")
    end)

    it("can rotate to the next terminal", function()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev() -- to set the term back to first
        term.next()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, second_buf_id, "Next didnt go to the second buffer")
    end)

    it("can rotate to the first terminal when next at the last terminal", function()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.next()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, first_buf_id, "After next win at the last terminal it wraps back around to first")
    end)

    it("only rotates between project terminals", function()
        local first_proj_win = term.open()
        local first_proj_buf_id = vim.api.nvim_win_get_buf(first_proj_win)
        term.close()
        vim.fn.chdir(test_proj_2)
        local win_id = term.open_new_terminal()
        term.open_new_terminal()

        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= first_proj_buf_id)
        term.next()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= first_proj_buf_id)
        term.next()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= first_proj_buf_id)
        term.prev()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= first_proj_buf_id)
        term.prev()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= first_proj_buf_id)
    end)

    it("kills terminals", function()
        local initial_bufs = #vim.api.nvim_list_bufs()
        term.open_new_terminal()
        term.open_new_terminal()
        vim.fn.chdir(test_proj_2)
        term.open_new_terminal()
        term.open_new_terminal()
        local bufs_after_opens = #vim.api.nvim_list_bufs()

        term.kill()

        local bufs_after_kill = #vim.api.nvim_list_bufs()
        assert(bufs_after_opens > initial_bufs, "Didnt open any bufs")
        eq(bufs_after_kill, initial_bufs, "Buf count didnt go back to normal")
    end)

    it("opens terminal at specified path", function()
        local specific_path = vim.fs.joinpath(test_proj, "specific")
        setup_path(specific_path)

        local win_id = term.open_at_path(specific_path)

        local buf_id = assert_terminal_opened(win_id)
        assert(term_opt_spy[buf_id] ~= nil and term_opt_spy[buf_id] == specific_path, "Specific path wasnt opened")
    end)

    it("vim notifies when attempt to open specific path outside of project", function()
        local outside_proj_path = vim.fs.joinpath(test_proj_2, "specific")

        local win_id = term.open_at_path(outside_proj_path)

        assert(win_id == nil, "A window was opened when it shouldnt")
        assert(notifySpy, string.format("Path '%s' is not within project '%s'", outside_proj_path, test_proj))
    end)
end)
