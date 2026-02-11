-- inline.lua
-- Inline agentic coding: stream AI output directly into the buffer

local api = require("utils.ai.api")
local debug = require("utils.ai.debug")

local M = {}

local NO_CODE_SENTINEL = "__NO_INLINE_CODE_PROMPT__"

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Namespace for virtual text extmarks
local ns_id = vim.api.nvim_create_namespace("ai_inline_spinner")

-- Spinner state
local spinner_state = {
    timer = nil,
    frame = 1,
    buf = nil,
    top_extmark = nil,
    bottom_extmark = nil,
}

--- Start the spinner with virtual lines above and below the selection
--- @param buf number Buffer ID
--- @param start_row number 0-indexed start row
--- @param end_row number 0-indexed end row
local function start_spinner(buf, start_row, end_row)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    spinner_state.buf = buf
    spinner_state.frame = 1

    local function get_spinner_text()
        return spinner_frames[spinner_state.frame] .. " thinking..."
    end

    -- Create extmark above the selection (virt_lines_above on start_row)
    spinner_state.top_extmark = vim.api.nvim_buf_set_extmark(buf, ns_id, start_row, 0, {
        virt_lines_above = true,
        virt_lines = { { { get_spinner_text(), "Comment" } } },
    })

    -- Create extmark below the selection (virt_lines on end_row)
    spinner_state.bottom_extmark = vim.api.nvim_buf_set_extmark(buf, ns_id, end_row, 0, {
        virt_lines = { { { get_spinner_text(), "Comment" } } },
    })

    -- Start timer to animate the spinner
    local timer = vim.uv.new_timer()
    spinner_state.timer = timer

    timer:start(80, 80, vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(spinner_state.buf) then
            M.stop_spinner()
            return
        end

        spinner_state.frame = (spinner_state.frame % #spinner_frames) + 1
        local text = get_spinner_text()

        -- Update top extmark
        if spinner_state.top_extmark then
            pcall(vim.api.nvim_buf_set_extmark, spinner_state.buf, ns_id, start_row, 0, {
                id = spinner_state.top_extmark,
                virt_lines_above = true,
                virt_lines = { { { text, "Comment" } } },
            })
        end

        -- Update bottom extmark
        if spinner_state.bottom_extmark then
            pcall(vim.api.nvim_buf_set_extmark, spinner_state.buf, ns_id, end_row, 0, {
                id = spinner_state.bottom_extmark,
                virt_lines = { { { text, "Comment" } } },
            })
        end
    end))
end

--- Stop the spinner and remove virtual lines
function M.stop_spinner()
    if spinner_state.timer then
        spinner_state.timer:stop()
        spinner_state.timer:close()
        spinner_state.timer = nil
    end

    if spinner_state.buf and vim.api.nvim_buf_is_valid(spinner_state.buf) then
        vim.api.nvim_buf_clear_namespace(spinner_state.buf, ns_id, 0, -1)
    end

    spinner_state.top_extmark = nil
    spinner_state.bottom_extmark = nil
    spinner_state.buf = nil
    spinner_state.frame = 1
end

--- Execute an inline edit: stream AI response into the buffer, replacing the selection
--- @param selection table {buf, start_row, start_col, end_row, end_col, text}
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context
--- @param history table|nil Optional conversation history
function M.execute(selection, instruction, context, history)
    debug.log("inline.execute called")
    debug.log("Selection: " .. selection.start_row .. ":" .. selection.start_col ..
        " to " .. selection.end_row .. ":" .. selection.end_col)

    local buf = selection.buf
    if not vim.api.nvim_buf_is_valid(buf) then
        vim.notify("AI Inline: Buffer is no longer valid", vim.log.levels.ERROR)
        return
    end

    -- Start the spinner around the selection
    start_spinner(buf, selection.start_row, selection.end_row)

    -- Track accumulated response to detect sentinel
    local response_chunks = {}
    local first_chunk = true

    -- Track current insertion position (will update as we stream)
    local insert_row = selection.start_row
    local insert_col = selection.start_col

    -- Delete the selected region first, then stream in the replacement
    local function prepare_buffer()
        -- Stop spinner before modifying buffer
        M.stop_spinner()

        vim.api.nvim_buf_set_text(
            buf,
            selection.start_row, selection.start_col,
            selection.end_row, selection.end_col,
            {}
        )
    end

    local function insert_text(text)
        -- Split text into lines
        local lines = vim.split(text, "\n", { plain = true })

        if #lines == 0 then
            return
        end

        -- Get the current line at insert position
        local current_line = vim.api.nvim_buf_get_lines(buf, insert_row, insert_row + 1, false)[1] or ""

        if #lines == 1 then
            -- Single line: insert inline
            local before = current_line:sub(1, insert_col)
            local after = current_line:sub(insert_col + 1)
            local new_line = before .. lines[1] .. after
            vim.api.nvim_buf_set_lines(buf, insert_row, insert_row + 1, false, { new_line })
            insert_col = insert_col + #lines[1]
        else
            -- Multiple lines: insert first part inline, then new lines
            local before = current_line:sub(1, insert_col)
            local after = current_line:sub(insert_col + 1)

            -- First line: append to current position
            local first_line = before .. lines[1]

            -- Middle lines: insert as-is
            local middle_lines = {}
            for i = 2, #lines - 1 do
                table.insert(middle_lines, lines[i])
            end

            -- Last line: prepend what comes after the original cursor
            local last_line = lines[#lines] .. after

            -- Build the replacement
            local replacement = { first_line }
            for _, line in ipairs(middle_lines) do
                table.insert(replacement, line)
            end
            table.insert(replacement, last_line)

            vim.api.nvim_buf_set_lines(buf, insert_row, insert_row + 1, false, replacement)

            -- Update position to end of inserted text
            insert_row = insert_row + #lines - 1
            insert_col = #lines[#lines]
        end
    end

    local cancel = api.inline_stream(
        selection.text,
        instruction,
        context,
        history,
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)

            -- Check for sentinel (might come across multiple chunks)
            local full_response = table.concat(response_chunks, "")
            if full_response:find(NO_CODE_SENTINEL, 1, true) then
                -- Don't insert anything, we'll notify on completion
                return
            end

            if first_chunk then
                first_chunk = false
                prepare_buffer()
            end

            insert_text(delta)
        end,
        -- on_done
        function()
            M.stop_spinner()
            local full_response = table.concat(response_chunks, "")

            -- Check for sentinel
            if full_response:find(NO_CODE_SENTINEL, 1, true) then
                vim.notify("AI Inline: No code edit detected in your instruction", vim.log.levels.WARN)
                return
            end

            -- If we never inserted anything (empty response), notify
            if first_chunk then
                vim.notify("AI Inline: No response received", vim.log.levels.WARN)
                return
            end

            debug.log("Inline edit complete, inserted " .. #full_response .. " chars")
        end,
        -- on_error
        function(err)
            M.stop_spinner()
            vim.notify("AI Inline: " .. err, vim.log.levels.ERROR)
        end
    )

    if not cancel then
        vim.notify("AI Inline: Failed to start request", vim.log.levels.ERROR)
    end
end

return M
