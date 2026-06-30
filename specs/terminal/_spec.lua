---@diagnostic disable: duplicate-set-field, param-type-mismatch

local t = require("specs.terminal.testing")
local assert_eq = assert.are.same

describe("Floating terminal", function()
	local sut = require("utils.terminal")
	local test_proj = vim.fs.joinpath(vim.fn.stdpath("cache"), "terminal-test")
	local test_proj_2 = vim.fs.joinpath(vim.fn.stdpath("cache"), "terminal-test-2")
	t.setup_path(test_proj)
	t.setup_path(test_proj_2)
	t.spy_on_term_open()
	t.spy_on_notify()

	before_each(function()
		t.reset()
		sut.kill()
		vim.fn.chdir(test_proj)
	end)

	it("opens the terminal without setup", function()
		local win_id = sut.open()

		local buf_id = t.assert_terminal_opened_floating(win_id)
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
        t.should_open_term_at(buf_id, 'proj_path', 'Should pass the pwd and not a speifix path')
        t.should_find_terminal({ not_including = buf_id, preloaded = true })
	end)

	it("setup preloads a terminal", function()
		sut.setup_for_project()

        t.should_find_terminal({ preloaded = true })
	end)

	it("processes opens idempotently", function()
		local win_count_before = #vim.api.nvim_list_wins()

		local _ = sut.open()
		local win_id = sut.open()

		local buf_id = t.assert_terminal_opened_floating(win_id)
		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_before + 1, "Only one new window should have opened")
        t.should_find_terminal({ not_including = buf_id, preloaded = true })
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
	end)

	it("opens new terminal in new project", function()
		local arranged = t.arrange_terminals(sut, { opened = { proj = test_proj } })

		vim.fn.chdir(test_proj_2)
		local win_id = sut.open()

		local buf_id_proj2 = t.assert_terminal_opened_floating(win_id)
        assert(win_id ~= nil, "Window should open")
		assert(arranged.buf_id ~= buf_id_proj2, "Same buffer shouldnt be used for both projects")
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
	end)

	it("snap terminal snaps to the botright", function()
		t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		local snapped_win_id = sut.snap()

		t.assert_terminal_opened_snapped(snapped_win_id)
	end)

	it("snap focuses the previously active editor window", function()
		local original_win_id = vim.api.nvim_get_current_win()
		t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		local snapped_win_id = sut.snap()

		t.assert_terminal_opened_snapped(snapped_win_id)
		assert_eq(vim.api.nvim_get_current_win(), original_win_id, "Snap should return focus to the previous window")
	end)

	it("snap prefers the alternate window when multiple editor windows exist", function()
		vim.cmd("vsplit")
		local second_editor_win_id = vim.api.nvim_get_current_win()
		t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		local snapped_win_id = sut.snap()

		t.assert_terminal_opened_snapped(snapped_win_id, 3)
		assert_eq(
			vim.api.nvim_get_current_win(),
			second_editor_win_id,
			"Snap should focus the alternate editor window when it is valid"
		)
		assert(
			second_editor_win_id ~= snapped_win_id,
			"Sanity check: alternate editor window should not be the snapped terminal"
		)
	end)

	it("snap does nothing when no window is open", function()
		local win_id = sut.snap()

		assert(win_id == nil, "snap should return nil when no window is open")
		local win_count = #vim.api.nvim_list_wins()
		assert_eq(win_count, 1, "No new windows should have opened")
	end)

	it("snap toggles back to float from vsplit", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj } })

		local float_win_id = sut.snap()

		t.assert_terminal_opened_floating(float_win_id)
		local curr_buf_id = vim.api.nvim_win_get_buf(float_win_id)
		assert_eq(curr_buf_id, arranged.buf_id, "Should still show the same terminal buffer after toggling")
        t.assert_terminal_tab_indicator(float_win_id, ' ◆ ')
	end)

	it("open when snapped returns to float", function()
		t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj } })

		local float_win_id = sut.open()

		t.assert_terminal_opened_floating(float_win_id)
        t.assert_terminal_tab_indicator(float_win_id, ' ◆ ')
	end)

	it("close when snapped closes the window", function()
		local win_count_before = #vim.api.nvim_list_wins()
		t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj } })

		sut.close()

		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_before, "Window wasnt closed")
	end)

	it("can rotate terminals while snapped", function()
        local arranged = t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj }, other = { test_proj } })
		local buf_before = vim.api.nvim_win_get_buf(arranged.win_id)

		sut.next()

		local buf_after = vim.api.nvim_win_get_buf(arranged.win_id)
		assert(buf_before ~= buf_after, "Rotate should change the buffer while snapped")
		t.assert_terminal_opened_snapped(arranged.win_id)
	end)

	it("can open new terminal while snapped", function()
        local arranged = t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj }, other = { test_proj } })
		local buf_before = vim.api.nvim_win_get_buf(arranged.win_id)

		sut.open_new_terminal()

		local buf_after = vim.api.nvim_win_get_buf(arranged.win_id)
		assert(buf_before ~= buf_after, "New terminal should show a different buffer while snapped")
	end)

	it("can delete current terminal while snapped", function()
        local arranged = t.arrange_terminals(sut, { opened = { win = 'snapped', proj = test_proj }, other = { test_proj } })
		local buf_before = vim.api.nvim_win_get_buf(arranged.win_id)

		sut.delete_curr()

		assert_eq(
			vim.api.nvim_win_is_valid(arranged.win_id),
			true,
			"Window should still be valid after delete with multiple terms"
		)
		assert_eq(vim.api.nvim_buf_is_valid(buf_before), false, "Deleted terminal buffer should be invalid")
	end)

	it("closes the window when one is open", function()
		local win_count_before = #vim.api.nvim_list_wins()
        t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		sut.close()

		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_before, "Window should have closed")
	end)

	it("closes window idempotently", function()
		local win_count_before = #vim.api.nvim_list_wins()
        t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		sut.close()
		sut.close()

		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_before, "Window wasnt closed")
	end)

	it("opens a new terminal", function()
		local win_id = sut.open_new_terminal()

		local buf_id = t.assert_terminal_opened_floating(win_id)
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
        t.should_find_terminal({ not_including = buf_id, preloaded = true })
	end)

	it("open_new_terminal opens new terminal when one already exists", function()
		local win_count_before = #vim.api.nvim_list_wins()
        local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		local win_id_2 = sut.open_new_terminal()

		assert(arranged.win_id == win_id_2, "Different windows were used when it should be just one")
		local buf_id_2 = t.assert_terminal_opened_floating(win_id_2)
		assert(arranged.buf_id ~= buf_id_2, "Same buffer used each time but should be different")
		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_before + 1, "More than 1 new window opened")
        t.assert_terminal_tab_indicator(win_id_2, ' ◇◆ ')
	end)

	it("can rotate to the prev terminal", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj }, other = { test_proj } })
		local first_buf_id = arranged.buf_id
		local win_id = arranged.win_id

		sut.prev()

		local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		assert(curr_buf_id ~= first_buf_id, "Prev didnt go back to the previous term")
        t.assert_terminal_tab_indicator(win_id, ' ◆◇ ')
	end)

	it("can rotate to the last terminal if preving from first terminal", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj }, other = { test_proj } })
		local first_buf_id = arranged.buf_id
		local win_id = arranged.win_id

		sut.prev()
		sut.prev()

		local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		assert_eq(curr_buf_id, first_buf_id, "Prev didnt wrap around to the last buffer")
        t.assert_terminal_tab_indicator(win_id, ' ◇◆ ')
	end)

	it("can rotate to the first terminal when next at the last terminal", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj }, other = { test_proj } })
		local first_buf_id = arranged.buf_id
		local win_id = arranged.win_id

		sut.next()

		local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		assert(curr_buf_id ~= first_buf_id, "Next didnt go to the next buffer")
        t.assert_terminal_tab_indicator(win_id, ' ◆◇ ')
	end)

	it("can rotate to the next terminal", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj }, other = { test_proj } })
		local first_buf_id = arranged.buf_id
		local win_id = arranged.win_id

		sut.next()
		sut.next()

		local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		assert_eq(curr_buf_id, first_buf_id, "After next win at the last terminal it wraps back around to first")
        t.assert_terminal_tab_indicator(win_id, ' ◇◆ ')
	end)

	it("only rotates between project terminals", function()
		vim.fn.chdir(test_proj_2)
		local second_proj = t.arrange_terminals(sut, {
			opened = { win = 'floating', proj = test_proj_2 },
			other = { test_proj, test_proj_2 },
		})
		local win_id = second_proj.win_id

		local curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		t.should_open_term_at(curr_buf_id, test_proj_2, "Initial term should not be from proj 1")
		sut.next()
		curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		t.should_open_term_at(curr_buf_id, test_proj_2, "After next(1) should not be from proj 1")
		sut.next()
		curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		t.should_open_term_at(curr_buf_id, test_proj_2, "After next(2) should not be from proj 1")
		sut.prev()
		curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		t.should_open_term_at(curr_buf_id, test_proj_2, "After prev(1) should not be from proj 1")
		sut.prev()
		curr_buf_id = vim.api.nvim_win_get_buf(win_id)
		t.should_open_term_at(curr_buf_id, test_proj_2, "After prev(2) should not be from proj 1")
	end)

	it("kills terminals", function()
		local initial_bufs = #vim.api.nvim_list_bufs()
		t.arrange_terminals(sut, {
			opened = { win = 'floating', proj = test_proj },
			other = { test_proj, test_proj_2, test_proj_2 },
		})
		local bufs_after_opens = #vim.api.nvim_list_bufs()

		sut.kill()

		local bufs_after_kill = #vim.api.nvim_list_bufs()
		assert(bufs_after_opens > initial_bufs, "Didnt open any bufs")
		assert_eq(bufs_after_kill, initial_bufs, "Buf count didnt go back to normal")
	end)

	it("opens terminal at specified path", function()
		local specific_path = vim.fs.joinpath(test_proj, "specific")
		t.setup_path(specific_path)

		local win_id = sut.open_at_path(specific_path)

		local buf_id = t.assert_terminal_opened_floating(win_id)
		local captured_path = t.term_opt_spy[buf_id]
		assert(captured_path ~= nil, "Path spy didnt capture terminal cwd")
		assert_eq(vim.fs.normalize(captured_path), vim.fs.normalize(specific_path), "Specific path wasnt opened")
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
	end)

	it("vim notifies when attempt to open specific path outside of project", function()
		local outside_proj_path = vim.fs.joinpath(test_proj_2, "specific")

		local win_id = sut.open_at_path(outside_proj_path)

		assert(win_id == nil, "A window was opened when it shouldnt")
		local normalized_path = vim.fs.normalize(vim.fn.fnamemodify(outside_proj_path, ':p'))
		local normalized_proj = vim.fs.normalize(vim.fn.fnamemodify(test_proj, ':p'))
		if not vim.endswith(normalized_proj, '/') then
			normalized_proj = normalized_proj .. '/'
		end
		assert_eq(
			t.notify_spy,
			string.format('Path "%s" is not within project "%s"', normalized_path, normalized_proj),
			"Incorrect notification was sent"
		)
	end)

	it("deletes curr terminal and closes the window if one term is open", function()
		local win_count_start = #vim.api.nvim_list_wins()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj } })

		sut.delete_curr()

		assert_eq(vim.api.nvim_win_is_valid(arranged.win_id), false, "The opened win didnt close")
		local win_count_after = #vim.api.nvim_list_wins()
		assert_eq(win_count_after, win_count_start, "The window wasnt closed")
	end)

	it("deletes curr terminal and attaches next term if multiple terms are open", function()
		local arranged = t.arrange_terminals(sut, { opened = { win = 'floating', proj = test_proj }, other = { test_proj } })
		local win_id = arranged.win_id
		local curr_term_buf_id = vim.api.nvim_win_get_buf(win_id)

		sut.delete_curr()

		assert_eq(vim.api.nvim_win_is_valid(win_id), true, "The win wasnt valid but should be")
		assert_eq(vim.api.nvim_buf_is_valid(curr_term_buf_id), false, "The current term buffer wasnt deleted")
		local updated_buf_id = vim.api.nvim_win_get_buf(win_id)
		assert(updated_buf_id ~= curr_term_buf_id, "The next term wasnt attached")
		assert_eq(vim.api.nvim_buf_is_valid(updated_buf_id), true, "The next term buffer isnt valid")
        t.assert_terminal_tab_indicator(win_id, ' ◆ ')
	end)

	it("delete curr terminal when nothing is loaded does nothing", function()
		sut.delete_curr()

		assert(true, "delete_curr on empty state should not error")
	end)
end)
