-- inline.lua
-- Inline agentic coding: stream AI output directly into the buffer

local api = require("utils.ai.api")
local debug = require("utils.ai.debug")
local spinner_mod = require("utils.ai.spinner")

local M = {}

-- Namespace for virtual text extmarks
local ns_id = vim.api.nvim_create_namespace("ai_inline_spinner")

-- Spinner state
local spinner_state = {
    spinner = nil,
    buf = nil,
    top_extmark = nil,
    bottom_extmark = nil,
}

--- Start the spinner with virtual lines above and below the selection
--- @param buf number Buffer ID
--- @param start_row number 0-indexed start row
--- @param end_row number 0-indexed end row
--- @param indent string Indentation to match surrounding code
local function start_spinner(buf, start_row, end_row, indent)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    spinner_state.buf = buf
    local prefix = indent or ""

    spinner_state.spinner = spinner_mod.create({
        on_frame = function(frame)
            if not vim.api.nvim_buf_is_valid(spinner_state.buf) then
                M.stop_spinner()
                return
            end

            local text = prefix .. frame .. " thinking..."

            if not spinner_state.top_extmark then
                spinner_state.top_extmark = vim.api.nvim_buf_set_extmark(buf, ns_id, start_row, 0, {
                    virt_lines_above = true,
                    virt_lines = { { { text, "Comment" } } },
                })
                spinner_state.bottom_extmark = vim.api.nvim_buf_set_extmark(buf, ns_id, end_row, 0, {
                    virt_lines = { { { text, "Comment" } } },
                })
            else
                pcall(vim.api.nvim_buf_set_extmark, spinner_state.buf, ns_id, start_row, 0, {
                    id = spinner_state.top_extmark,
                    virt_lines_above = true,
                    virt_lines = { { { text, "Comment" } } },
                })
                pcall(vim.api.nvim_buf_set_extmark, spinner_state.buf, ns_id, end_row, 0, {
                    id = spinner_state.bottom_extmark,
                    virt_lines = { { { text, "Comment" } } },
                })
            end
        end,
    })
    spinner_state.spinner.start()
end

--- Stop the spinner and remove virtual lines
function M.stop_spinner()
    if spinner_state.spinner then
        spinner_state.spinner.stop()
        spinner_state.spinner = nil
    end

    if spinner_state.buf and vim.api.nvim_buf_is_valid(spinner_state.buf) then
        vim.api.nvim_buf_clear_namespace(spinner_state.buf, ns_id, 0, -1)
    end

    spinner_state.top_extmark = nil
    spinner_state.bottom_extmark = nil
    spinner_state.buf = nil
end

--- Execute an inline edit: stream AI response into the buffer, replacing the selection
--- @param selection table {buf, filename, start_row, start_col, end_row, end_col, text, lines_before, lines_after, indent}
--- @param instruction string The user's instruction
--- @param context string|nil Optional buffer context (other open files)
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
    start_spinner(buf, selection.start_row, selection.end_row, selection.indent)

    -- Track accumulated response
    local response_chunks = {}

    -- Track current insertion position
    local insert_row = selection.start_row
    local insert_col = selection.start_col

    -- Delete the selected region first, then stream in the replacement
    local function prepare_buffer()
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

    --- Strip markdown code fences from response if present
    local function strip_fences(text)
        -- Match opening fence with optional language identifier
        local stripped = text:match("^```[^\n]*\n(.*)$")
        if stripped then
            -- Remove closing fence
            stripped = stripped:gsub("\n?```%s*$", "")
            return stripped
        end
        return text
    end

    --- Apply indentation to each line of the response
    local function apply_indent(text, indent)
        if not indent or indent == "" then
            return text
        end
        local lines = vim.split(text, "\n", { plain = true })
        for i, line in ipairs(lines) do
            -- Only indent non-empty lines that don't already have the indent
            if line ~= "" and not line:match("^" .. indent) then
                -- Strip any existing leading whitespace and apply correct indent
                lines[i] = indent .. line:gsub("^%s*", "")
            end
        end
        return table.concat(lines, "\n")
    end

    local cancel = api.inline_stream(
        selection.text,
        instruction,
        context,
        history,
        selection.lines_before,
        selection.lines_after,
        selection.indent,
        selection.filename,
        selection.start_row + 1, -- convert 0-indexed to 1-indexed
        selection.end_row + 1,
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)
        end,
        -- on_done
        function()
            M.stop_spinner()

            local full_response = table.concat(response_chunks, "")

            -- If empty response, notify
            if full_response == "" then
                vim.notify("AI Inline: No response received", vim.log.levels.WARN)
                return
            end

            -- Strip markdown fences if the model included them
            local clean_response = strip_fences(full_response)

            -- Apply correct indentation
            clean_response = apply_indent(clean_response, selection.indent)

            -- Replace the selection with the clean response
            prepare_buffer()
            insert_text(clean_response)

            debug.log("Inline response:\n" .. full_response)
        end,
        -- on_error
        function(err)
            M.stop_spinner()
            vim.notify("AI Inline: " .. err, vim.log.levels.ERROR)
            debug.log("AI Inline: " .. err)
        end
    )

    if not cancel then
        vim.notify("AI Inline: Failed to start request", vim.log.levels.ERROR)
    end
end

return M
