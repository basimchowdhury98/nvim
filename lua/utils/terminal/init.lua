-- floating-terminal.lua
-- a floating terminal that mimics telescope's ui design

local M = {}

if vim.fn.has('mac') == 1 then
	vim.opt.shell = '/bin/zsh'
	vim.opt.shellcmdflag = '-c'
	vim.opt.shellquote = ''
	vim.opt.shellxquote = ''
elseif vim.fn.has('linux') == 1 then
	vim.opt.shell = '/bin/bash'
	vim.opt.shellcmdflag = '-c'
	vim.opt.shellquote = ''
	vim.opt.shellxquote = ''
else
	vim.opt.shell = 'pwsh'
	vim.opt.shellcmdflag = '-command'
	vim.opt.shellquote = '"'
	vim.opt.shellxquote = ''
end

local config = {
	width_ratio = 0.8,
	height_ratio = 0.8,
	border = 'rounded',
	title = ' Terminal ',
	prompt_title = ' Command ',
}

local state = {
	win_id = nil,
	proj_current_term = {},
}

local proj_terms = {}

local preloaded_terms = {}

local map = vim.keymap.set
local lto = 'FTerm - Open'
map('n', '<leader>to', function () M.open() end, { desc = lto })
local ltk = 'FTerm - Kill all'
map('n', '<leader>tk', function () M.kill() end, { desc = ltk })
local ltd = 'FTerm - Debug'
map('n', '<leader>td', function () M.debug() end, { desc = ltd })
local ltj = 'FTerm - Open at file directory'
map('n', '<leader>tj', function()
    local file_dir = vim.fn.expand('%:p:h')
    require('utils.terminal').open_at_path(file_dir)
end, { desc = ltj })

local function set_term_keymaps(buf_id)
    local cf = 'FTerm - Rotate next'
	map({ 't', 'n' }, '<C-f>', function () M.next() end, { buffer = buf_id, desc = cf })
    local ca = 'F- Rotate prev'
	map({ 't', 'n' }, '<C-a>', function () M.prev() end, { buffer = buf_id, desc = ca })
    local ck = 'F- Escape mode to normal'
	map('t', '<C-j>', '<C-\\><C-n>', { buffer = buf_id, desc = ck })
    local cs = 'F- Snap to split/snap back to float'
	map({ 't', 'n' }, '<C-s>', function () M.snap() end, { buffer = buf_id, desc = cs })
    local co = 'Open a new nal'
    map({ 't', 'n' }, '<C-o>', function () M.open_new_terminal() end, { buffer = buf_id, desc = co })
    local cd = 'F- Kill/Delete current nal'
    map({ 't', 'n' }, '<C-k>', function () M.delete_curr() end, { buffer = buf_id, desc = cd })
end

local function get_curr_proj()
	return vim.fn.getcwd()
end

local function window_is_open()
	return state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

local function window_is_snapped()
    if not state.win_id then
        return false
    end

    local win_conf = vim.api.nvim_win_get_config(state.win_id)
    if win_conf.relative == 'editor' then
        return false
    end

    return true
end

local function calc_window_dims()
	local width = math.floor(vim.o.columns * config.width_ratio)
	local height = math.floor(vim.o.lines * config.height_ratio)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)
	return { width = width, height = height, row = row, col = col }
end

local function create_terminal_buffer(path)
	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.bo[buf_id].bufhidden = 'hide'
	vim.bo[buf_id].swapfile = false

	set_term_keymaps(buf_id)

	local term = {
		buf_id = buf_id,
	}
	vim.api.nvim_buf_call(buf_id, function()
		if path == nil then
			term.term_job_id = vim.fn.termopen(vim.o.shell)
			return
		end
		term.term_job_id = vim.fn.termopen(vim.o.shell, { cwd = path })
	end)

	return term
end

local function attach_term(term)
	local curr_proj = get_curr_proj()
	local terms = proj_terms[curr_proj]
	if terms == nil then
		terms = {}
		proj_terms[curr_proj] = terms
	end

	table.insert(terms, term)
	state.proj_current_term[curr_proj] = term
end

local function refresh_window()
	if not window_is_open() then
		return
	end

	local curr_proj = get_curr_proj()
	vim.api.nvim_win_set_buf(state.win_id, state.proj_current_term[curr_proj].buf_id)
end

local function open_window()
	if window_is_open() then
		return
	end

	local curr_proj = get_curr_proj()
	local dims = calc_window_dims()

	-- Window options that match Telescope's style
	local win_opts = {
		relative = 'editor',
		width = dims.width,
		height = dims.height,
		row = dims.row,
		col = dims.col,
		style = 'minimal',
		border = config.border,
		title = config.title,
		title_pos = 'center',
	}
	state.win_id = vim.api.nvim_open_win(state.proj_current_term[curr_proj].buf_id, true, win_opts)

	-- Set window options to match Telescope using modern API
	vim.wo[state.win_id].winhighlight = 'Normal:TelescopeNormal,FloatBorder:TelescopeBorder,Title:TelescopeTitle'
	vim.cmd('startinsert')
end

local function close_window()
	if not window_is_open() then
		return
	end

	vim.api.nvim_win_close(state.win_id, false)
	state.win_id = nil
end

local function rotate_next()
	if not window_is_open() then
		return
	end

	if next(proj_terms) == nil then
		vim.notify('No terminals spawned')
		return
	end
	local proj = get_curr_proj()

	local terms = proj_terms[proj]
	if #terms == 0 then
		vim.notify('No terminals for this project spawned')
		return
	end

	local nextTerm = -1
	for index, term in ipairs(terms) do
		if index == #terms then
			nextTerm = 1
			break
		end
		if state.proj_current_term[proj].buf_id == term.buf_id then
			nextTerm = index + 1
			break
		end
	end
	state.proj_current_term[proj] = terms[nextTerm]
	refresh_window()
end

local function rotate_prev()
	if not window_is_open() then
		return
	end

	if next(proj_terms) == nil then
		vim.notify('No terminals spawned')
		return
	end
	local proj = get_curr_proj()

	local terms = proj_terms[proj]
	if #terms == 0 then
		vim.notify('No terminals for this project spawned')
		return
	end

	local nextTerm = -1
	for i = #terms, 1, -1 do
		if i == 1 then
			nextTerm = #terms
			break
		end
		local term = terms[i]
		if state.proj_current_term[proj].buf_id == term.buf_id then
			nextTerm = i - 1
			break
		end
	end
	state.proj_current_term[proj] = terms[nextTerm]
	refresh_window()
end

local function preload()
	local curr_proj = get_curr_proj()
	local existing = preloaded_terms[curr_proj]
	if existing ~= nil then
		return
	end

	local term = create_terminal_buffer()
	preloaded_terms[curr_proj] = term
end

local function get_alternate_window()
	local alt_winnr = vim.fn.winnr('#')
	if alt_winnr == 0 then
		return nil
	end

	local alt_win_id = vim.fn.win_getid(alt_winnr)
	if alt_win_id == 0 or not vim.api.nvim_win_is_valid(alt_win_id) then
		return nil
	end

	return alt_win_id
end

local function focus_snap_target(alternate_win_id, prior_wins)
	local seen = {}
	local candidates = {}

	if alternate_win_id ~= nil then
		table.insert(candidates, alternate_win_id)
	end

	for i = #prior_wins, 1, -1 do
		table.insert(candidates, prior_wins[i])
	end

	for _, win_id in ipairs(candidates) do
		if not seen[win_id]
			and win_id ~= state.win_id
			and vim.api.nvim_win_is_valid(win_id)
		then
			vim.api.nvim_set_current_win(win_id)
			return
		end
		seen[win_id] = true
	end
end

function M.open_new_terminal()
	local curr_proj = get_curr_proj()

	local term
	if preloaded_terms[curr_proj] ~= nil then
		term = preloaded_terms[curr_proj]
		preloaded_terms[curr_proj] = nil
	else
		term = create_terminal_buffer()
	end

	attach_term(term)

	if window_is_open() then
		refresh_window()
	else
		open_window()
	end

	preload()

	return state.win_id
end

function M.setupForProject()
	preload()
end

local function snap_to_vsplit()
	local prior_wins = vim.api.nvim_list_wins()
	local alternate_win_id = get_alternate_window()
    close_window()
	local curr_proj = get_curr_proj()
	local buf_id = state.proj_current_term[curr_proj].buf_id

	vim.cmd('botright vsplit')
	state.win_id = vim.api.nvim_get_current_win()
	vim.wo[state.win_id].winhighlight = 'Normal:TelescopeNormal'
	vim.api.nvim_win_set_buf(state.win_id, buf_id)

    vim.cmd('stopinsert')
	focus_snap_target(alternate_win_id, prior_wins)
end

function M.open()
	local curr_proj = get_curr_proj()

	if window_is_open() then
        if window_is_snapped() then
            close_window()
            open_window()
        end
		return state.win_id
	end
	if state.proj_current_term[curr_proj] == nil then
		M.open_new_terminal()
	else
		open_window()
	end
	return state.win_id
end

function M.close()
	close_window()
end

function M.delete_curr()
	local curr_proj = get_curr_proj()
	local terms = proj_terms[curr_proj]
	local curr_term = state.proj_current_term[curr_proj]

	if terms == nil or #terms == 0 then
		return
	elseif #terms == 1 then
		state.proj_current_term[curr_proj] = nil
		close_window()
	else
		rotate_next()
	end

	for i, v in ipairs(terms) do
		if v == curr_term then
			table.remove(terms, i)
			break
		end
	end

	if curr_term.term_job_id then
		vim.fn.jobstop(curr_term.term_job_id)
	end
	if curr_term.buf_id and vim.api.nvim_buf_is_valid(curr_term.buf_id) then
		vim.api.nvim_buf_delete(curr_term.buf_id, { force = true })
	end
end

function M.kill()
	close_window()
	for _, terms in pairs(proj_terms) do
		for _, term in ipairs(terms) do
			if term.term_job_id then
				vim.fn.jobstop(term.term_job_id)
			end
			if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
				vim.api.nvim_buf_delete(term.buf_id, { force = true })
			end
		end
	end
	for _, term in pairs(preloaded_terms) do
		if term.term_job_id then
			vim.fn.jobstop(term.term_job_id)
		end
		if term.buf_id and vim.api.nvim_buf_is_valid(term.buf_id) then
			vim.api.nvim_buf_delete(term.buf_id, { force = true })
		end
	end

	state.proj_current_term = nil
	state.proj_current_term = {}
	proj_terms = {}
	preloaded_terms = {}

	vim.notify('Killed floating terminal')
end

function M.next()
	rotate_next()
end

function M.prev()
	rotate_prev()
end

function M.debug()
	print('Proj terms: ' .. vim.inspect(proj_terms))
	print('State: ' .. vim.inspect(state))
	print('Preloaded: ' .. vim.inspect(preloaded_terms))
end

function M.open_at_path(path)
	local curr_proj = get_curr_proj()

	local normalized_path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
	local normalized_proj = vim.fs.normalize(vim.fn.fnamemodify(curr_proj, ':p'))
	if not vim.endswith(normalized_proj, '/') then
		normalized_proj = normalized_proj .. '/'
	end
	if not vim.startswith(normalized_path, normalized_proj) then
		vim.notify(
			string.format('Path "%s" is not within project "%s"', normalized_path, normalized_proj),
			vim.log.levels.WARN
		)
		return
	end

	local term = create_terminal_buffer(path)
	attach_term(term)
	open_window()

	return state.win_id
end

function M.snap()
	if not window_is_open() then
		return
	end

    if window_is_snapped() then
        close_window()
        open_window()
        return state.win_id
    end
	snap_to_vsplit()

	return state.win_id
end

vim.api.nvim_create_autocmd('VimResized', {
	callback = function()
		if not window_is_open() then
			return
		end
		if window_is_snapped() then
			return
		end

		local dims = calc_window_dims()
		vim.api.nvim_win_set_config(state.win_id, {
			relative = 'editor',
			width = dims.width,
			height = dims.height,
			row = dims.row,
			col = dims.col,
		})
	end,
})

return M
