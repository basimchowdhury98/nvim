local eq = assert.are.same

describe("Floating terminal", function()
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
    end)

    it("opens the terminal when none exists", function()
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
    end)

    it("processes opens idempotently", function()
        local win_count_before = #vim.api.nvim_list_wins()

        local _ = term.open()
        local win_id = term.open()

        assert(win_id ~= nil)
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        assert(buf_id ~= nil)
        local win_count_after = #vim.api.nvim_list_wins()
        eq(win_count_after, win_count_before + 1, "One new window should be open after")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
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
        eq(buf_count_after, buf_count_before + 2, "Two new buffers should be open after")
        local term_job_id = vim.b[buf_id].terminal_job_id
        assert(term_job_id ~= nil and term_job_id > 0, "Term job should have started")
        local term_job_id_2 = vim.b[buf_id_2].terminal_job_id
        assert(term_job_id_2 ~= nil and term_job_id_2 > 0, "Term job should have started")
        assert(term_job_id ~= term_job_id_2)
    end)
end)
