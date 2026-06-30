local M = {}

local config = {
    width_ratio = 0.8,
    height_ratio = 0.8,
    border = 'rounded',
    active_term_indic = '◆',
    inative_term_indic = '◇',
    prompt_title = ' Command ',
}

local function calc_window_dims()
    local width = math.floor(vim.o.columns * config.width_ratio)
    local height = math.floor(vim.o.lines * config.height_ratio)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    return { width = width, height = height, row = row, col = col }
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

local function focus_snap_target(snapped_win_id, alternate_win_id, prior_wins)
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
            and win_id ~= snapped_win_id
            and vim.api.nvim_win_is_valid(win_id)
        then
            vim.api.nvim_set_current_win(win_id)
            return
        end
        seen[win_id] = true
    end
end

local function set_term_tabs_indicator(win_id, term_pos)
    local term_tab_indicator = ''
    for i = 1, term_pos.terms_count do
        if i == term_pos.index then
            term_tab_indicator = term_tab_indicator .. config.active_term_indic
        else
            term_tab_indicator = term_tab_indicator .. config.inative_term_indic
        end
    end
    vim.api.nvim_win_set_config(win_id, {
        title = ' ' .. term_tab_indicator .. ' ',
        title_pos = 'center',
    })
end

local function set_float_title_highlight()
    local title_hl = vim.api.nvim_get_hl(0, { name = 'TelescopeTitle', link = false })
    local terminal_title_hl = vim.tbl_extend('force', {}, title_hl, { bg = nil, base = nil })
    vim.api.nvim_set_hl(0, 'TerminalFloatTitle', terminal_title_hl)
end

function M.snap_to_vsplit(win_id)
    local prior_wins = vim.api.nvim_list_wins()
    local alternate_win_id = get_alternate_window()
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    vim.api.nvim_win_close(win_id, false)

    vim.cmd('botright vsplit')
    local snapped_win_id = vim.api.nvim_get_current_win()
    vim.wo[snapped_win_id].winhighlight = 'Normal:TelescopeNormal'
    vim.api.nvim_win_set_buf(snapped_win_id, buf_id)

    vim.cmd('stopinsert')
    focus_snap_target(snapped_win_id, alternate_win_id, prior_wins)

    return snapped_win_id
end

function M.window_is_open(win_id)
    return vim.api.nvim_win_is_valid(win_id)
end

function M.window_is_snapped(win_id)
    local win_conf = vim.api.nvim_win_get_config(win_id)
    if win_conf.relative == 'editor' then
        return false
    end

    return true
end

function M.set_win_term(win_id, buf_id, term_pos)
    vim.api.nvim_win_set_buf(win_id, buf_id)
    set_term_tabs_indicator(win_id, term_pos)
end

function M.close_win(win_id)
    vim.api.nvim_win_close(win_id, false)
end

function M.vim_resized(win_id)
    local dims = calc_window_dims()
    vim.api.nvim_win_set_config(win_id, {
        relative = 'editor',
        width = dims.width,
        height = dims.height,
        row = dims.row,
        col = dims.col,
    })
end

function M.open_float(term_buf, term_pos)
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
    }
    local win_id = vim.api.nvim_open_win(term_buf, true, win_opts)

    -- Set window options to match Telescope using modern API
    set_float_title_highlight()
    vim.wo[win_id].winhighlight = 'Normal:TelescopeNormal,FloatBorder:TelescopeBorder,FloatTitle:TerminalFloatTitle'
    vim.cmd('startinsert')

    set_term_tabs_indicator(win_id, term_pos)
    return win_id
end

return M
