-- chat.lua
-- Chat buffer management: right-side split, read-only, message rendering

local spinner = require("utils.ai.spinner")

local M = {}

local default_config = {
    split_width = 80,
    title = "AI Chat",
}

local config = vim.deepcopy(default_config)

local ns = vim.api.nvim_create_namespace("ai_chat")

local state = {
    buf_id = nil,
    win_id = nil,
    is_streaming = false,
    spinner = nil,
    spinner_line = nil, -- 0-indexed line where the spinner lives
    set_spinner_label = nil, -- function to change spinner label text
    user_section_start = nil, -- 0-indexed line where user section begins
    assistant_section_start = nil, -- 0-indexed line where assistant section starts (for post-processing)
    thinking_section_start = nil, -- 0-indexed line where thinking section starts
    thinking_expanded = false, -- whether thinking blocks are currently shown
    thinking_blocks = {}, -- {line = 0-indexed, content = string}[] for toggle
}

-- Define highlight groups by linking to standard groups (adapts to any colorscheme)
local function setup_highlights()
    local set = vim.api.nvim_set_hl
    set(0, "AIChatUserHeader", { link = "Title", default = true })
    set(0, "AIChatUserBg", { link = "TabLine", default = true })
    set(0, "AIChatAssistantHeader", { link = "Function", default = true })
    set(0, "AIChatError", { link = "ErrorMsg", default = true })
    set(0, "AIChatInterrupted", { link = "Comment", default = true })
    set(0, "AIChatSeparator", { link = "NonText", default = true })
    set(0, "AIChatBold", { bold = true, default = true })
    set(0, "AIChatCodeBlock", { link = "CursorLine", default = true })
    set(0, "AIChatInlineCode", { link = "CursorLine", default = true })
    set(0, "AIChatThinkingIndicator", { link = "Comment", default = true })
    set(0, "AIChatThinkingContent", { link = "Comment", default = true })
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
    setup_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        callback = setup_highlights,
    })
end

local function buf_is_valid()
    return state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id)
end

local function win_is_valid()
    return state.win_id and vim.api.nvim_win_is_valid(state.win_id)
end

--- Apply a line-level highlight (background) to a range of lines
--- @param start_line number 0-indexed start line
--- @param end_line number 0-indexed end line (exclusive)
--- @param hl_group string highlight group name
local function highlight_lines(start_line, end_line, hl_group)
    if not buf_is_valid() then return end
    for line = start_line, end_line - 1 do
        vim.api.nvim_buf_set_extmark(state.buf_id, ns, line, 0, {
            line_hl_group = hl_group,
        })
    end
end

--- Apply a highlight to a specific line's text
--- @param line number 0-indexed line
--- @param hl_group string highlight group name
local function highlight_text(line, hl_group)
    if not buf_is_valid() then return end
    local text = vim.api.nvim_buf_get_lines(state.buf_id, line, line + 1, false)[1] or ""
    if #text > 0 then
        vim.api.nvim_buf_set_extmark(state.buf_id, ns, line, 0, {
            end_col = #text,
            hl_group = hl_group,
        })
    end
end

local function create_buf()
    if buf_is_valid() then
        return state.buf_id
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "aichat"
    vim.api.nvim_buf_set_name(buf, "ai-chat")

    state.buf_id = buf
    return buf
end

local function scroll_to_bottom()
    if not win_is_valid() then return end
    local line_count = vim.api.nvim_buf_line_count(state.buf_id)
    vim.api.nvim_win_set_cursor(state.win_id, { line_count, 0 })
end

--- Run a function with the buffer temporarily modifiable
local function with_modifiable(fn)
    if not buf_is_valid() then return end
    vim.bo[state.buf_id].modifiable = true
    fn()
    vim.bo[state.buf_id].modifiable = false
end

--- Strip markdown markers from a line, returning cleaned text and a list of
--- {start, len, hl} entries (0-indexed byte positions in the cleaned string).
--- @param line string
--- @return string cleaned
--- @return table[] highlights
local function strip_inline_markdown(line)
    local segments = {} -- {text, hl_group|nil}
    local pos = 1

    while pos <= #line do
        -- Try **bold**
        local bs, be, bold_text = line:find("%*%*(.-)%*%*", pos)
        -- Try `code`
        local cs, ce, code_text = line:find("`([^`]+)`", pos)

        -- Pick whichever comes first
        if bs and (not cs or bs <= cs) then
            if bs > pos then
                table.insert(segments, { text = line:sub(pos, bs - 1) })
            end
            table.insert(segments, { text = bold_text, hl = "AIChatBold" })
            pos = be + 1
        elseif cs then
            if cs > pos then
                table.insert(segments, { text = line:sub(pos, cs - 1) })
            end
            table.insert(segments, { text = code_text, hl = "AIChatInlineCode" })
            pos = ce + 1
        else
            table.insert(segments, { text = line:sub(pos) })
            break
        end
    end

    local cleaned = {}
    local highlights = {}
    local col = 0
    for _, seg in ipairs(segments) do
        table.insert(cleaned, seg.text)
        if seg.hl then
            table.insert(highlights, { start = col, len = #seg.text, hl = seg.hl })
        end
        col = col + #seg.text
    end

    return table.concat(cleaned), highlights
end

--- Post-process assistant lines: strip markdown syntax and apply extmark highlights.
--- Handles **bold**, inline `code`, and ```fenced code blocks```.
--- @param from_line number 0-indexed first line of assistant content
--- @param to_line number 0-indexed last line (exclusive)
local function apply_markdown_highlights(from_line, to_line)
    if not buf_is_valid() then return end
    local lines = vim.api.nvim_buf_get_lines(state.buf_id, from_line, to_line, false)
    local in_code_block = false
    local code_block_start = nil

    for i, line in ipairs(lines) do
        local line_idx = from_line + i - 1

        if line:match("^```") then
            if not in_code_block then
                in_code_block = true
                code_block_start = line_idx
                -- Hide the opening fence line
                with_modifiable(function()
                    vim.api.nvim_buf_set_lines(state.buf_id, line_idx, line_idx + 1, false, { "" })
                end)
            else
                -- Hide the closing fence line
                with_modifiable(function()
                    vim.api.nvim_buf_set_lines(state.buf_id, line_idx, line_idx + 1, false, { "" })
                end)
                if code_block_start then
                    highlight_lines(code_block_start, line_idx + 1, "AIChatCodeBlock")
                end
                in_code_block = false
                code_block_start = nil
            end
        elseif not in_code_block then
            local cleaned, highlights = strip_inline_markdown(line)
            if cleaned ~= line then
                with_modifiable(function()
                    vim.api.nvim_buf_set_lines(state.buf_id, line_idx, line_idx + 1, false, { cleaned })
                end)
            end
            for _, hl in ipairs(highlights) do
                vim.api.nvim_buf_set_extmark(state.buf_id, ns, line_idx, hl.start, {
                    end_col = hl.start + hl.len,
                    hl_group = hl.hl,
                    priority = 200,
                })
            end
        end
    end

    if in_code_block and code_block_start then
        highlight_lines(code_block_start, to_line, "AIChatCodeBlock")
    end
end

--- Remove the spinner line from the buffer (does not stop the timer)
local function remove_spinner_line()
    if state.spinner_line and buf_is_valid() then
        with_modifiable(function()
            vim.api.nvim_buf_set_lines(state.buf_id, state.spinner_line, state.spinner_line + 1, false, {})
        end)
        state.spinner_line = nil
    end
end

--- Add a spinner line at the bottom of the buffer (does not start the timer)
local function add_spinner_line()
    if not buf_is_valid() then return end
    with_modifiable(function()
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        vim.api.nvim_buf_set_lines(state.buf_id, line_count, line_count, false, { "" })
        state.spinner_line = line_count
    end)
end

--- Stop the spinner and remove the spinner line from the buffer
local function stop_spinner()
    if state.spinner then
        state.spinner.stop()
        state.spinner = nil
    end
    remove_spinner_line()
end

--- Start an animated spinner on the last line of the chat buffer
local function start_spinner()
    if not buf_is_valid() then return end

    add_spinner_line()
    scroll_to_bottom()

    local label = "Thinking..."

    state.spinner = spinner.create({
        on_frame = function(frame)
            if not buf_is_valid() or not state.spinner_line then
                stop_spinner()
                return
            end
            with_modifiable(function()
                vim.api.nvim_buf_set_lines(
                    state.buf_id,
                    state.spinner_line,
                    state.spinner_line + 1,
                    false,
                    { frame .. " " .. label }
                )
            end)
        end,
    })
    state.spinner.start()

    return function(new_label)
        label = new_label
    end
end

function M.open()
    if win_is_valid() then
        vim.api.nvim_set_current_win(state.win_id)
        return
    end

    local buf = create_buf()

    -- Open a vertical split on the right
    vim.cmd("botright vsplit")
    state.win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win_id, buf)
    local editor_width = vim.o.columns
    local width = math.min(config.split_width, math.floor(editor_width * 0.3))
    vim.api.nvim_win_set_width(state.win_id, width)

    -- Window-local options
    vim.wo[state.win_id].number = false
    vim.wo[state.win_id].relativenumber = false
    vim.wo[state.win_id].signcolumn = "no"
    vim.wo[state.win_id].wrap = true
    vim.wo[state.win_id].linebreak = true
    vim.wo[state.win_id].cursorline = false

    scroll_to_bottom()

    -- Return focus to the previous window
    vim.cmd("wincmd p")
end

function M.close()
    if win_is_valid() then
        vim.api.nvim_win_close(state.win_id, false)
        state.win_id = nil
    end
end

function M.toggle()
    if win_is_valid() then
        M.close()
    else
        M.open()
    end
end

function M.is_open()
    return win_is_valid()
end

--- Append lines of text to the chat buffer
--- @param lines string[] Lines to append
--- @return number start_line 0-indexed start line of the appended content
local function append_lines(lines)
    if not buf_is_valid() then return 0 end

    local start_line = 0
    with_modifiable(function()
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        local first_line = vim.api.nvim_buf_get_lines(state.buf_id, 0, 1, false)
        if line_count == 1 and first_line[1] == "" then
            start_line = 0
            vim.api.nvim_buf_set_lines(state.buf_id, 0, 1, false, lines)
        else
            start_line = line_count
            vim.api.nvim_buf_set_lines(state.buf_id, line_count, line_count, false, lines)
        end
    end)
    scroll_to_bottom()
    return start_line
end

--- Append a user message to the chat buffer
--- @param text string The user's message
function M.append_user_message(text)
    local lines = { "---", "", "You:", "" }
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    local start = append_lines(lines)

    -- Track user section for background highlighting
    state.user_section_start = start

    -- Highlight separator
    highlight_text(start, "AIChatSeparator")
    -- Highlight header (start + 2 = "You:" line)
    highlight_text(start + 2, "AIChatUserHeader")
    -- Highlight all user section lines with background
    highlight_lines(start + 2, start + #lines, "AIChatUserBg")
end

--- Start an assistant response block in the chat buffer
function M.start_assistant_message()
    local start = append_lines({ "", "Assistant:", "" })

    -- Track assistant section start for post-processing
    state.assistant_section_start = start + 2
    -- Track thinking section (same line where response starts)
    state.thinking_section_start = start + 2

    -- Highlight header
    highlight_text(start + 1, "AIChatAssistantHeader")

    state.is_streaming = true
    state.set_spinner_label = start_spinner()
end

--- Append a streaming text delta to the current assistant response
--- @param text string The text chunk to append
function M.append_delta(text)
    if not buf_is_valid() then return end

    -- Switch spinner label from "Thinking..." to "Streaming..." on first delta
    if state.set_spinner_label then
        state.set_spinner_label("Streaming...")
        state.set_spinner_label = nil
    end

    -- Temporarily remove the spinner line so we append text above it
    remove_spinner_line()

    -- Split delta by newlines
    local parts = {}
    local i = 1
    while i <= #text do
        local nl = text:find("\n", i, true)
        if nl then
            table.insert(parts, text:sub(i, nl - 1))
            i = nl + 1
        else
            table.insert(parts, text:sub(i))
            i = #text + 1
        end
    end
    if text:sub(-1) == "\n" then
        table.insert(parts, "")
    end

    if #parts > 0 then
        with_modifiable(function()
            local line_count = vim.api.nvim_buf_line_count(state.buf_id)
            local last_line = vim.api.nvim_buf_get_lines(state.buf_id, line_count - 1, line_count, false)[1] or ""

            local new_last = last_line .. parts[1]
            vim.api.nvim_buf_set_lines(state.buf_id, line_count - 1, line_count, false, { new_last })

            if #parts > 1 then
                local new_lines = {}
                for j = 2, #parts do
                    table.insert(new_lines, parts[j])
                end
                local updated_count = vim.api.nvim_buf_line_count(state.buf_id)
                vim.api.nvim_buf_set_lines(state.buf_id, updated_count, updated_count, false, new_lines)
            end
        end)
    end

    -- Re-add spinner line below the new content
    if state.spinner then
        add_spinner_line()
    end
    scroll_to_bottom()
end

--- Append a streaming thinking chunk to the chat (shows in real-time before response)
--- @param text string The thinking text chunk to append
function M.append_thinking(text)
    if not buf_is_valid() then return end

    -- Switch spinner label from "Thinking..." to "Streaming..." on first thinking
    if state.set_spinner_label then
        state.set_spinner_label("Thinking...")
        state.set_spinner_label = nil
    end

    -- Remove spinner temporarily
    remove_spinner_line()

    -- Insert thinking before the assistant section (after "Assistant:" header)
    local insert_line = state.thinking_section_start
    if not insert_line then
        return
    end

    local parts = {}
    local i = 1
    while i <= #text do
        local nl = text:find("\n", i, true)
        if nl then
            table.insert(parts, text:sub(i, nl - 1))
            i = nl + 1
        else
            table.insert(parts, text:sub(i))
            i = #text + 1
        end
    end
    if text:sub(-1) == "\n" then
        table.insert(parts, "")
    end

    if #parts > 0 then
        with_modifiable(function()
            -- Get current thinking section line
            local existing_line = vim.api.nvim_buf_get_lines(state.buf_id, insert_line, insert_line + 1, false)[1] or ""

            -- Append first part to existing line
            local new_existing = existing_line .. parts[1]
            vim.api.nvim_buf_set_lines(state.buf_id, insert_line, insert_line + 1, false, { new_existing })

            -- Add remaining parts as new lines
            if #parts > 1 then
                local new_lines = {}
                for j = 2, #parts do
                    table.insert(new_lines, parts[j])
                end
                local updated_count = vim.api.nvim_buf_line_count(state.buf_id)
                vim.api.nvim_buf_set_lines(state.buf_id, updated_count, updated_count, false, new_lines)
            end
        end)
    end

    -- Re-add spinner line
    if state.spinner then
        add_spinner_line()
    end
    scroll_to_bottom()
end

--- Finish the current assistant response
--- @param thinking string|nil The model's thinking/reasoning output, if any
function M.finish_assistant_message(thinking)
    stop_spinner()
    state.set_spinner_label = nil

    -- Calculate thinking line count from the thinking string
    local thinking_line_count = 0
    if thinking and #thinking > 0 then
        for _ in thinking:gmatch("[^\n]+") do
            thinking_line_count = thinking_line_count + 1
        end
    end

    -- Post-process: strip markdown syntax and apply highlights
    -- We apply to the whole section, then replace thinking with indicator
    if state.assistant_section_start and buf_is_valid() then
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        apply_markdown_highlights(state.assistant_section_start, line_count)
    end

    -- Replace streaming thinking with collapsed indicator if thinking exists
    if thinking and #thinking > 0 and buf_is_valid() and state.thinking_section_start then
        local line_count_label = thinking_line_count == 1 and "1 line" or (thinking_line_count .. " lines")
        local indicator = "  Thinking... (" .. line_count_label .. ")"

        local insert_line = state.thinking_section_start

        with_modifiable(function()
            -- Delete the thinking lines that were added during streaming
            local delete_end = insert_line + thinking_line_count
            vim.api.nvim_buf_set_lines(state.buf_id, insert_line, delete_end, false, {})

            -- Insert the indicator at the same position
            vim.api.nvim_buf_set_lines(state.buf_id, insert_line, insert_line, false, { indicator })
        end)

        highlight_text(insert_line, "AIChatThinkingIndicator")

        table.insert(state.thinking_blocks, {
            line = insert_line,
            content = thinking,
        })

        -- Shift assistant_section_start: was at insert_line + thinking_line_count,
        -- now indicator is at insert_line, so response starts at insert_line + 1
        state.assistant_section_start = insert_line + 1
    end

    -- Add trailing empty lines
    append_lines({ "", "" })

    state.is_streaming = false
end

--- Append a complete assistant message (for re-rendering saved conversations)
--- @param text string The assistant's full response
function M.append_assistant_content(text)
    local lines = { "", "Assistant:", "" }
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    local start = append_lines(lines)

    highlight_text(start + 1, "AIChatAssistantHeader")
    apply_markdown_highlights(start + 2, start + #lines)
end

--- Show an error in the chat buffer
--- @param msg string Error message
function M.append_error(msg)
    stop_spinner()
    state.set_spinner_label = nil
    local error_lines = { "" }
    local msg_lines = vim.split(msg, "\n", { plain = true })
    for i, line in ipairs(msg_lines) do
        if i == 1 then
            table.insert(error_lines, "Error: " .. line)
        else
            table.insert(error_lines, line)
        end
    end
    table.insert(error_lines, "")
    local start = append_lines(error_lines)
    for i = 1, #msg_lines do
        highlight_text(start + i, "AIChatError")
    end
    state.is_streaming = false
end

--- Mark the current response as interrupted
function M.append_interrupted()
    stop_spinner()
    state.set_spinner_label = nil

    -- Post-process what we have so far before adding interrupted marker
    if state.assistant_section_start and buf_is_valid() then
        local line_count = vim.api.nvim_buf_line_count(state.buf_id)
        apply_markdown_highlights(state.assistant_section_start, line_count)
    end

    local start = append_lines({ "", "", "[interrupted]", "" })
    highlight_text(start + 2, "AIChatInterrupted")
    state.is_streaming = false
end

--- Clear the chat buffer
function M.clear()
    stop_spinner()
    state.set_spinner_label = nil
    state.user_section_start = nil
    state.assistant_section_start = nil
    state.thinking_blocks = {}
    state.thinking_expanded = false
    if not buf_is_valid() then return end
    vim.api.nvim_buf_clear_namespace(state.buf_id, ns, 0, -1)
    with_modifiable(function()
        vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, { "" })
    end)
    state.is_streaming = false
end

--- Toggle visibility of all thinking blocks in the chat buffer
function M.toggle_thinking()
    if not buf_is_valid() or #state.thinking_blocks == 0 then
        return
    end

    if state.thinking_expanded then
        -- Collapse: remove expanded thinking lines, restore indicators
        -- Process blocks in reverse order to keep line numbers stable
        for i = #state.thinking_blocks, 1, -1 do
            local block = state.thinking_blocks[i]
            local thinking_lines = {}
            for line in block.content:gmatch("([^\n]*)\n?") do
                table.insert(thinking_lines, line)
            end
            if #thinking_lines > 0 and thinking_lines[#thinking_lines] == "" then
                table.remove(thinking_lines)
            end

            local line_count_label = #thinking_lines == 1 and "1 line" or (#thinking_lines .. " lines")
            local indicator = "  Thinking... (" .. line_count_label .. ")"

            -- The expanded block spans from block.line to block.line + #thinking_lines
            with_modifiable(function()
                vim.api.nvim_buf_set_lines(state.buf_id, block.line, block.line + #thinking_lines, false, { indicator })
            end)
            highlight_text(block.line, "AIChatThinkingIndicator")
        end
        state.thinking_expanded = false
    else
        -- Expand: replace indicator lines with full thinking content
        -- Process blocks in reverse order to keep line numbers stable
        for i = #state.thinking_blocks, 1, -1 do
            local block = state.thinking_blocks[i]
            local thinking_lines = {}
            for line in block.content:gmatch("([^\n]*)\n?") do
                table.insert(thinking_lines, line)
            end
            if #thinking_lines > 0 and thinking_lines[#thinking_lines] == "" then
                table.remove(thinking_lines)
            end

            -- Replace the indicator line with thinking content
            with_modifiable(function()
                vim.api.nvim_buf_set_lines(state.buf_id, block.line, block.line + 1, false, thinking_lines)
            end)
            for j = 0, #thinking_lines - 1 do
                highlight_text(block.line + j, "AIChatThinkingContent")
            end
        end
        state.thinking_expanded = true
    end
end

function M.is_streaming()
    return state.is_streaming
end

function M.get_state()
    return vim.deepcopy(state)
end

return M
