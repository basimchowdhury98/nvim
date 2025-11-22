local eq = assert.are.same
local original_temropen = vim.fn.termopen
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

describe("Floating terminal", function()
    vim.fn.termopen = original_temropen
    local term = require("utils.terminal")

    before_each(function()
        term.kill()
        -- Close all windows except the first one (default window)
        local wins = vim.api.nvim_list_wins()
        for _, win in ipairs(wins) do
            if vim.api.nvim_win_is_valid(win) and win ~= wins[1] then
                pcall(vim.api.nvim_win_close, win, true)
            end
        end

        -- Delete all buffers except the first one (default buffer)
        local bufs = vim.api.nvim_list_bufs()
        for _, buf in ipairs(bufs) do
            if vim.api.nvim_buf_is_valid(buf) and buf ~= bufs[1] then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end

        vim.fn.getcwd = function() return "/stub/proj" end
    end)

    it("opens the terminal without setup", function()
        local win_count_before = #vim.api.nvim_list_wins()

        local win_id = term.open()

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "One new window should be open after")
        local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf_id })
        eq(buftype, 'terminal', "Buffer should be a terminal")
        local config = vim.api.nvim_win_get_config(win_id)
        eq(config.title[1][1], ' Terminal ', "Should have correct title")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
        local preloaded_next_term = findPreloadedTerm(buf_id)
        assert(preloaded_next_term ~= nil and preloaded_next_term ~= buf_id, "Should preload a terminal after done")
    end)

    it("opens window with setup uses a preloaded term", function()
        term.setupForProject()
        local preloaded_term_buf = findPreloadedTerm()

        local win_id = term.open()

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf_id })
        eq(buftype, 'terminal', "Buffer should be a terminal")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
        assert(preloaded_term_buf ~= nil)
        eq(buf_id, preloaded_term_buf)
        local preloaded_next_term = findPreloadedTerm(buf_id)
        assert(preloaded_next_term ~= nil and preloaded_next_term ~= buf_id, "Should preload a terminal after done")
    end)

    it("processes opens idempotently", function()
        local win_count_before = #vim.api.nvim_list_wins()
        local buf_count_before = #vim.api.nvim_list_bufs()

        local _ = term.open()
        local win_id = term.open()

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "One new window should be open after")
        local buf_count_after = #vim.api.nvim_list_bufs()
        eq(buf_count_after, buf_count_before + 2, "2 bufs should be open, one active, one preload")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
    end)

    it("opens new terminal in new project", function()
        local win_id_proj1 = term.open()
        local buf_id_proj1 = vim.api.nvim_win_get_buf(win_id_proj1)
        term.close()
        vim.fn.getcwd = function() return "/stub2/newproj" end
        local win_id_proj2 = term.open()
        local buf_id_proj2 = vim.api.nvim_win_get_buf(win_id_proj2)

        assert(win_id_proj1 ~= nil)
        assert(win_id_proj2 ~= nil)
        assert(buf_id_proj1 ~= nil)
        assert(buf_id_proj2 ~= nil)
        assert(win_id_proj1 ~= win_id_proj2, "Different windows since window needs to be closed first")
        assert(buf_id_proj1 ~= buf_id_proj2, "Different buffer per project")
    end)

    it("closes the window when one is open", function ()
        local win_count_before = #vim.api.nvim_list_wins()
        local win_id = term.open()

        term.close()

        assert(win_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before, "A win shouldve opened and closed")
    end)

    it("closes window idempotently", function ()
        local win_count_before = #vim.api.nvim_list_wins()
        local win_id = term.open()

        term.close()
        term.close()

        assert(win_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before, "A win shouldve opened and closed")
    end)

    it("opens a new terminal", function ()
        local win_count_before = #vim.api.nvim_list_wins()

        local win_id = term.open_new_terminal()

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "One new window should be open after")
        local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf_id })
        eq(buftype, 'terminal', "Buffer should be a terminal")
        local config = vim.api.nvim_win_get_config(win_id)
        eq(config.title[1][1], ' Terminal ', "Should have correct title")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
    end)

    it("opens 2 new terminals when_open_new terminal called twice", function ()
        local win_count_before = #vim.api.nvim_list_wins()
        local buf_count_before = #vim.api.nvim_list_bufs()

        local win_id = term.open_new_terminal()
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        local win_id_2 = term.open_new_terminal()
        local buf_id_2 = vim.api.nvim_win_get_buf(win_id)

        assert(win_id ~= nil)
        assert(win_id_2 ~= nil)
        assert(buf_id ~= nil)
        assert(buf_id_2 ~= nil)
        assert(win_id == win_id_2)
        assert(buf_id ~= buf_id_2)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "One new window should be open after")
        local buf_count_after = #vim.api.nvim_list_bufs()
        eq(buf_count_after, buf_count_before + 3, "Three buffers, 2 active, 1 preloaded")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
        local term_job_id_2 = vim.b[buf_id_2].terminal_job_id
        assert(term_job_id_2 ~= nil and term_job_id_2 > 0, "Term job should have started")
        assert(term_job_id ~= term_job_id_2)
    end)

    it("can rotate to the prev terminal", function ()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, first_buf_id, "After prev win should go back to first buff")
    end)

    it("can rotate to the last terminal if preving from first terminal", function ()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev() --puts win on first term
        term.prev()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, second_buf_id, "After prev when at the beginning win should go wrap back to last buff")
    end)

    it("can rotate to the next terminal", function ()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.prev() -- to set the term back to first
        term.next()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, second_buf_id, "After next win should go forward to second buff")
    end)

    it("can rotate to the first terminal when next at the last terminal", function ()
        local win_id = term.open_new_terminal()
        local first_buf_id = vim.api.nvim_win_get_buf(win_id)
        term.open_new_terminal()
        local second_buf_id = vim.api.nvim_win_get_buf(win_id)

        term.next()

        assert(first_buf_id ~= second_buf_id)
        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        eq(curr_buf_id, first_buf_id, "After next win at the last terminal it wraps back around to first")
    end)

    it("only rotates between project terminals", function ()
        vim.fn.getcwd = function() return "/stub/diffproj" end
        local diff_proj_win = term.open()
        local diff_proj_buf_id = vim.api.nvim_win_get_buf(diff_proj_win)
        term.close()
        vim.fn.getcwd = function() return "stub/thisproj" end
        local win_id = term.open_new_terminal()
        term.open_new_terminal()

        local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= diff_proj_buf_id)
        term.next()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= diff_proj_buf_id)
        term.next()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= diff_proj_buf_id)
        term.prev()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= diff_proj_buf_id)
        term.prev()
        curr_buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(curr_buf_id ~= diff_proj_buf_id)
    end)

    it("kills terminals", function ()
        local initial_bufs = #vim.api.nvim_list_bufs()
        term.open_new_terminal()
        term.open_new_terminal()
        vim.fn.getcwd = function() return "/stub/diffproj" end
        term.open_new_terminal()
        term.open_new_terminal()
        local bufs_after_opens = #vim.api.nvim_list_bufs()

        term.kill()

        local bufs_after_kill = #vim.api.nvim_list_bufs()
        assert(bufs_after_opens > initial_bufs, "Should have opened some bufs")
        eq(bufs_after_kill, initial_bufs, "Buf count should go back to normal after kill")
    end)

    it("opens terminal at specified path", function ()
        local specificPath = "/stub/proj/specific"
        local optSpy
        vim.fn.termopen = function (_, opt)
            optSpy = opt
        end

        local win_id = term.open_at_path(specificPath)

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        assert(optSpy ~= nil and optSpy.cwd == specificPath, "Should open specific path")
    end)

    it("vim notifies when attempt to open specific path outside of project", function ()
        local outsideOfProj = "stub/diffproj/specific"
        local optSpy
        vim.fn.termopen = function (_, opt)
            optSpy = opt
        end

        local win_id = term.open_at_path(outsideOfProj)

        assert(win_id == nil, "No window should be open")
        assert(optSpy == nil, "No terminal should be spawned")
    end)
end)
