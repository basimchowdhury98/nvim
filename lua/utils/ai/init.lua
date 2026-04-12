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
			virt[i] = { { '', '' } }
		end
		vim.api.nvim_buf_set_extmark(
			buf_id,
			vim.api.nvim_create_namespace('bottom_up'),
			0,
			0,
			{ virt_lines = virt, virt_lines_above = true }
		)
		vim.api.nvim_win_call(ai_win, function()
			vim.cmd('normal! zb')
		end)
	end
end

-- doc finder feature: find relevant docs for what im doing and give me a list of
-- urls. Maybe have different sensitivity levels ie Learn level find me docs for everything
-- including the language im working on. Another level could only get stuff i seem to be
-- stuck on or getting wrong
function M.start()
	local buf_id = create_status_buf()
	ai_win = open_status_win(buf_id)
	local messages = {}

	local opencode_srv_cmd = { 'opencode', 'serve', '--port', '8989' }
	local op_srv_cmd_check = { 'pgrep', '-f', '[o]pencode serve --port 8989' }

	local existing_serv = vim.system(op_srv_cmd_check):wait()
	if existing_serv.code ~= 0 then
		vim.system(opencode_srv_cmd, { detach = true })
	end

	local opencode_co = coroutine.create(function()
        local co = coroutine.running()
		vim.system(
			{ 'curl', '-s', '-w', '\n%{http_code}', '-X', 'GET', 'localhost:8989/global/health' },
			{ text = true},
			function(res)
				vim.schedule(function()
					coroutine.resume(co, res)
				end)
			end
		)

		local health_res = coroutine.yield()
		local lines = vim.split(health_res.stdout, '\n')
		local status_code = tonumber(lines[#lines])
		table.remove(lines)
		if status_code ~= 200 then
			vim.notify('Health call failed', vim.log.levels.WARN)
			return
		end

		table.insert(messages, 'Opencode healthy')
		display_status_msgs(messages, buf_id)

		local session_body = vim.json.encode({ title = 'NVIM AI - Test session' })
		vim.system({
			'curl',
			'-s',
			'-w',
			'\n%{http_code}',
			'-X',
			'POST',
			'-H',
			'Content-Type: application/json',
			'-d',
			session_body,
			'localhost:8989/session',
		}, { text = true }, function(sesh_res)
			vim.schedule(function()
				coroutine.resume(co, sesh_res)
			end)
		end)
		local sesh_res = coroutine.yield()
		local sesh_lines = vim.split(sesh_res.stdout, '\n')
		status_code = tonumber(sesh_lines[#sesh_lines])
		table.remove(sesh_lines)
		if status_code ~= 200 then
			vim.notify('Session creation failed', vim.log.levels.WARN)
			return
		end

		local session = vim.json.decode(table.concat(sesh_lines, '\n'))
		table.insert(messages, 'Session created: ' .. session.id)
		display_status_msgs(messages, buf_id)
	end)

	table.insert(messages, 'Started')
	display_status_msgs(messages, buf_id)

    coroutine.resume(opencode_co)
end

function M.stop()
	if ai_win == nil then
		return
	end
	vim.api.nvim_win_close(ai_win, false)
	ai_win = nil
end

vim.keymap.set('n', '<leader>io', M.start, { desc = '' })
vim.keymap.set('n', '<leader>ic', M.stop, { desc = '' })
return M
