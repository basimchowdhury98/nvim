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

    it("Multiple opens only process once", function()
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

end)
