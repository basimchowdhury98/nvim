local eq = assert.are.same

describe("Floating terminal", function()
    local term = require("utils.terminal")
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
end)
