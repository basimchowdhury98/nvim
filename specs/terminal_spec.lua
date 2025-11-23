local eq = assert.are.same
local function findPreloadedTerm(ignoreBuf)
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        if ignoreBuf ~= nil and buf == ignoreBuf then
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

local function setupPath(path)
    if vim.fn.isdirectory(path) == 0 then
        vim.fn.mkdir(path, 'p')
    end
end

local function assertTerminalOpened(win_id)
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

local function assertAnotherTermPreloaded(buf_to_skip)
    local preloaded_next_term = findPreloadedTerm(buf_to_skip)
    assert(preloaded_next_term ~= nil and preloaded_next_term ~= buf_to_skip,
        "Didnt preload another term after done")
end

local termOptSpy
local function spyOnTermOpen()
    local orig = vim.fn.termopen
    vim.fn.termopen = function(_, opt)
        if opt == nil then
            orig(_)
        else
            orig(_, opt)
        end
        termOptSpy = opt
    end
end

local notifySpy
local function spyOnNotify()
    vim.notify = function (msg, _)
        notifySpy = msg
    end
end

local test_proj = vim.fn.stdpath("cache") .. "\\terminal-test"
local test_proj_2 = vim.fn.stdpath("cache") .. "\\terminal-test-2"
setupPath(test_proj)
setupPath(test_proj_2)
spyOnTermOpen()
spyOnNotify()

describe("Floating terminal", function()
    local term = require("utils.terminal")

    before_each(function()
        term.kill()
        vim.fn.chdir(test_proj)
    end)

    it("opens the terminal without setup", function()
        local win_id = term.open()

        local buf_id = assertTerminalOpened(win_id)
        assert(termOptSpy == nil, "A specific path was passed when it should be pwd/proj path")
        assertAnotherTermPreloaded(buf_id)
    end)

    it("opens window with setup uses a preloaded term", function()
        term.setupForProject()
        local preloaded_term_buf = findPreloadedTerm()

        local win_id = term.open()

        local buf_id = assertTerminalOpened(win_id)
        assert(preloaded_term_buf ~= nil)
        eq(buf_id, preloaded_term_buf, "Didnt use the preloaded term")
        assertAnotherTermPreloaded(buf_id)
    end)

    it("processes opens idempotently", function()
        local win_count_before = #vim.api.nvim_list_wins()
        local buf_count_before = #vim.api.nvim_list_bufs()

        local _ = term.open()
        local win_id = term.open()

        assertTerminalOpened(win_id)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "Only one new window should have opened")
        local buf_count_after = #vim.api.nvim_list_bufs()
        eq(buf_count_after, buf_count_before + 2,
            "Exactly 2 bufs should be created, active and preload")
    end)

    it("opens new terminal in new project", function()
        local win_id_proj1 = term.open()
        local buf_id_proj1 = assertTerminalOpened(win_id_proj1)
        term.close()
        vim.fn.chdir(test_proj_2)
        local win_id_proj2 = term.open()
        local buf_id_proj2 = assertTerminalOpened(win_id_proj2)

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

        assertTerminalOpened(win_id)
    end)

    it("opens 2 new terminals when_open_new terminal called twice", function()
        local win_count_before = #vim.api.nvim_list_wins()

        local win_id = term.open_new_terminal()
        local buf_id = assertTerminalOpened(win_id)
        local win_id_2 = term.open_new_terminal()

        assert(win_id == win_id_2, "Different windows were used when it should be just one")
        local buf_id_2 = assertTerminalOpened(win_id_2)
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
        local specificPath = test_proj .. "\\specific"
        setupPath(specificPath)

        local win_id = term.open_at_path(specificPath)

        local buf_id = assertTerminalOpened(win_id)
        assert(buf_id ~= nil)
        assert(termOptSpy ~= nil and termOptSpy.cwd == specificPath, "Specific path wasnt opened")
        termOptSpy = nil
    end)

    it("vim notifies when attempt to open specific path outside of project", function()
        local outside_proj_path = test_proj_2 .. "\\specific"

        local win_id = term.open_at_path(outside_proj_path)

        assert(win_id == nil, "A window was opened when it shouldnt")
        assert(notifySpy, string.format("Path '%s' is not within project '%s'", outside_proj_path, test_proj))
    end)
end)
