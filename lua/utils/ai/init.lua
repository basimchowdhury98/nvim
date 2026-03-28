local M = {}

local ai_win

local function create_status_buf()
	local buf_id = vim.api.nvim_create_buf(false, false)
	vim.bo[buf_id].buftype = "nofile"
	vim.bo[buf_id].bufhidden = "wipe"
	vim.bo[buf_id].swapfile = false
	vim.bo[buf_id].modifiable = false
	vim.bo[buf_id].buflisted = false

    return buf_id
end

local function open_status_win(buf_id)
	vim.cmd("botright vsplit")
	local win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win_id, buf_id)
	vim.api.nvim_win_set_width(win_id, 30)
	vim.wo[win_id].number = false
	vim.wo[win_id].relativenumber = false

    return win_id
end

local function display_status_msgs(messages, buf_id)
	local displayed_msgs = {}
	for i = #messages, 1, -1 do
		displayed_msgs[#displayed_msgs + 1] = messages[i]
	end
	vim.bo[buf_id].modifiable = true
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, displayed_msgs)
	vim.bo[buf_id].modifiable = false
	local win_height = vim.api.nvim_win_get_height(ai_win)
    local lines = vim.api.nvim_buf_line_count(buf_id)
	local padding = win_height - lines
	if padding > 0 then
		local virt = {}
		for i = 1, padding do
			virt[i] = { { "", "" } }
		end
		vim.api.nvim_buf_set_extmark(
			buf_id,
			vim.api.nvim_create_namespace("bottom_up"),
			0,
			0,
			{ virt_lines = virt, virt_lines_above = true }
		)
		vim.api.nvim_win_call(ai_win, function()
			vim.cmd("normal! zb")
		end)
	end
end

function M.start()
    local buf_id = create_status_buf()
    ai_win = open_status_win(buf_id)

	local messages = {}
	table.insert(messages, "Started")
	table.insert(messages, "next")

    display_status_msgs(messages, buf_id)
end

function M.stop()
	if ai_win == nil then
		return
	end
	vim.api.nvim_win_close(ai_win, false)
	ai_win = nil
end

vim.keymap.set("n", "<leader>io", M.start, { desc = "" })
vim.keymap.set("n", "<leader>ic", M.stop, { desc = "" })
return M
