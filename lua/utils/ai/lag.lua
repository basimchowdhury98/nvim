-- lag.lua
-- AI Lag Mode: watches buffer saves, diffs changes, sends to LLM for
-- automatic fixes/implementations within the changed regions.

local api = require("utils.ai.api")
local debug = require("utils.ai.debug")
local M = {}

-- Per-buffer state keyed by bufnr
-- Each entry: {
--   baseline = string[],       -- buffer snapshot at last user-initiated save
--   processing = bool,         -- LLM call in flight for this buffer
--   debounce_timer = uv_timer, -- debounce handle
--   autocmd_ids = number[],    -- registered autocmd ids
--   modifications = table[],   -- applied modifications with original code for revert
--   ns = number,               -- extmark namespace for this buffer
--   active_index = number|nil, -- index of nearest modification to cursor
--   working_extmarks = table,  -- extmark ids for "working..." indicators
-- }
local buffers = {}

-- Module-level config
local lag_config = {
    debounce_ms = 2000,
}

-- Namespace for working indicators (shared)
local ns_working = vim.api.nvim_create_namespace("ai_lag_working")

-- Diagnostic namespace (shared across all lag buffers)
local ns_diagnostic = vim.api.nvim_create_namespace("ai_lag_diagnostic")

-- Define highlight groups
local function setup_highlights()
    vim.api.nvim_set_hl(0, "AILagComment", { fg = "#6a6a6a", italic = true })
    vim.api.nvim_set_hl(0, "AILagActiveComment", { fg = "#9a9a9a", bold = true, italic = true })
    vim.api.nvim_set_hl(0, "AILagWorking", { fg = "#6a6a6a", italic = true })
    vim.api.nvim_set_hl(0, "AILagWorkingLine", { bg = "#1a1a2e" })
    vim.api.nvim_set_hl(0, "AILagLine", { bg = "#1a2e1a" })
    vim.api.nvim_set_hl(0, "AILagActiveLine", { bg = "#253d25" })
end

--- Compute a unified diff between two line arrays.
--- Returns a list of changed regions: { { start_line, end_line } }
--- Lines are 1-indexed and refer to positions in `new_lines`.
--- @param old_lines string[]
--- @param new_lines string[]
--- @return table[] regions
local function compute_diff_regions(old_lines, new_lines)
    -- Use vim.diff to get a unified diff, then parse hunks
    local old_text = table.concat(old_lines, "\n") .. "\n"
    local new_text = table.concat(new_lines, "\n") .. "\n"

    -- Handle empty buffers
    if #old_lines == 0 and #new_lines == 0 then
        return {}
    end
    if #old_lines == 1 and old_lines[1] == "" and #new_lines == 1 and new_lines[1] == "" then
        return {}
    end

    local diff = vim.diff(old_text, new_text, { result_type = "indices" })
    if not diff or #diff == 0 then
        return {}
    end

    local regions = {}
    for _, hunk in ipairs(diff) do
        -- hunk = { old_start, old_count, new_start, new_count }
        local new_start = hunk[3]
        local new_count = hunk[4]
        if new_count > 0 then
            table.insert(regions, { new_start, new_start + new_count - 1 })
        elseif new_count == 0 and new_start > 0 then
            -- Pure deletion: mark the line after the deletion point
            table.insert(regions, { new_start, new_start })
        end
    end
    return regions
end

--- Check whether a modification's line range falls within any of the diff regions.
--- @param mod_start number 1-indexed start line
--- @param mod_end number 1-indexed end line
--- @param regions table[] diff regions
--- @return boolean
local function is_within_diff(mod_start, mod_end, regions)
    for _, region in ipairs(regions) do
        local r_start, r_end = region[1], region[2]
        -- Overlap check: mod overlaps region if mod_start <= r_end and mod_end >= r_start
        if mod_start <= r_end and mod_end >= r_start then
            return true
        end
    end
    return false
end

--- Get the indentation of a line
--- @param line string
--- @return string
local function get_indent(line)
    return line:match("^(%s*)") or ""
end

--- Place "LAG: working..." virtual text and line highlights over diff regions.
--- @param bufnr number
--- @param regions table[] diff regions (1-indexed)
local function show_working_indicator(bufnr, regions)
    local state = buffers[bufnr]
    if not state then return end

    state.working_extmarks = {}
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for _, region in ipairs(regions) do
        local start_line = region[1] - 1 -- 0-indexed
        local end_line = region[2] - 1

        -- Virtual text "working..." above the first line of the region
        if start_line >= 0 and start_line < line_count then
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)[1] or ""
            local indent = get_indent(buf_line)
            local id = vim.api.nvim_buf_set_extmark(bufnr, ns_working, start_line, 0, {
                virt_lines_above = true,
                virt_lines = { { { indent .. "Lag: working...", "AILagWorking" } } },
            })
            table.insert(state.working_extmarks, id)
        end

        -- Line highlights on every line in the region
        for l = start_line, math.min(end_line, line_count - 1) do
            local id = vim.api.nvim_buf_set_extmark(bufnr, ns_working, l, 0, {
                line_hl_group = "AILagWorkingLine",
            })
            table.insert(state.working_extmarks, id)
        end
    end
end

--- Remove all "working..." indicators from a buffer.
--- @param bufnr number
local function clear_working_indicator(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_working, 0, -1)
    local state = buffers[bufnr]
    if state then
        state.working_extmarks = {}
    end
end

--- Clear all modification visual indicators from a buffer.
--- @param bufnr number
local function clear_modification_extmarks(bufnr)
    local state = buffers[bufnr]
    if not state then return end
    vim.api.nvim_buf_clear_namespace(bufnr, state.ns, 0, -1)
    vim.diagnostic.reset(ns_diagnostic, bufnr)
end

--- Format original code for diagnostic message display.
--- @param original_lines string[]
--- @return string
local function format_old_code(original_lines)
    if #original_lines == 0 then
        return "(empty)"
    end
    return table.concat(original_lines, "\n")
end

--- Render virtual text comments, line highlights, and diagnostics for all modifications.
--- Highlights the active one differently.
--- @param bufnr number
local function render_modifications(bufnr)
    local state = buffers[bufnr]
    if not state or #state.modifications == 0 then return end

    clear_modification_extmarks(bufnr)

    local diagnostics = {}

    for i, mod in ipairs(state.modifications) do
        local line = mod.line - 1 -- 0-indexed
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line >= 0 and line < line_count then
            local is_active = (i == state.active_index)
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
            local indent = get_indent(buf_line)
            local comment_hl = is_active and "AILagActiveComment" or "AILagComment"
            local line_hl = is_active and "AILagActiveLine" or "AILagLine"

            -- Virtual text comment above the modification
            vim.api.nvim_buf_set_extmark(bufnr, state.ns, line, 0, {
                virt_lines_above = true,
                virt_lines = { { { indent .. "Lag: " .. mod.comment, comment_hl } } },
            })

            -- Line highlights on all modified lines
            local end_line = math.min(line + #mod.new_lines, line_count)
            for l = line, end_line - 1 do
                vim.api.nvim_buf_set_extmark(bufnr, state.ns, l, 0, {
                    line_hl_group = line_hl,
                })
            end

            -- Diagnostic with old code for hover expansion
            table.insert(diagnostics, {
                bufnr = bufnr,
                lnum = line,
                end_lnum = math.min(line + #mod.new_lines - 1, line_count - 1),
                col = 0,
                severity = vim.diagnostic.severity.HINT,
                source = "lag",
                message = format_old_code(mod.original_lines),
            })
        end
    end

    vim.diagnostic.set(ns_diagnostic, bufnr, diagnostics)
end

--- Update which modification is closest to the cursor.
--- @param bufnr number
local function update_active(bufnr)
    local state = buffers[bufnr]
    if not state or #state.modifications == 0 then return end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local min_dist = math.huge
    local closest = nil

    for i, mod in ipairs(state.modifications) do
        local dist = math.abs(cursor_line - mod.line)
        if dist < min_dist then
            min_dist = dist
            closest = i
        end
    end

    if closest ~= state.active_index then
        state.active_index = closest
        render_modifications(bufnr)
    end
end

--- Build the system prompt for lag mode.
--- @return string
local function build_system_prompt()
    return [[You are a code review assistant integrated into the user's editor. The user just saved their file and you can see which lines changed (the diff regions).

Your job is LIMITED to the diff regions only. You must ONLY modify code within the changed regions. Do NOT touch any code outside the diff.

What you should do:
- Fix bugs or incorrect logic in the changed code
- Implement empty method/function bodies that appear in the diff
- Implement pseudocode described in comments within the diff — when you do this, REPLACE the comment/pseudocode with the actual implementation. The comment was an instruction to you, not documentation to keep.
- Fix syntax errors in the changed code

What you must NOT do:
- Modify code outside the diff regions
- Refactor or restyle code
- Add unsolicited features or improvements
- Change variable names or code structure unless it's genuinely broken

Respond with a JSON array of modifications. Each modification is an object:
{
  "start_line": <1-indexed line number where replacement starts>,
  "end_line": <1-indexed line number where replacement ends>,
  "replacement": "<the new code to replace lines start_line through end_line>",
  "comment": "<brief explanation of what you changed and why>"
}

If no changes are needed, respond with an empty array: []

CRITICAL: Every modification's start_line and end_line MUST fall within one of the diff regions provided. Any modification outside the diff regions will be rejected.

Respond with ONLY the JSON array, no other text.]]
end

--- Build the user prompt for a lag mode call.
--- @param bufnr number
--- @param diff_regions table[]
--- @param context_block string|nil
--- @param session table
--- @return string
local function build_lag_prompt(bufnr, diff_regions, context_block, session)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local ft = vim.bo[bufnr].filetype or ""

    local parts = {}

    -- Context from other buffers
    if context_block then
        table.insert(parts, context_block)
    end

    -- Chat history context
    if session and #session.conversation > 0 then
        table.insert(parts, "Recent chat history for context:")
        for _, msg in ipairs(session.conversation) do
            table.insert(parts, string.format("[%s]: %s", msg.role, msg.content))
        end
    end

    -- Current buffer
    local numbered = {}
    for i, line in ipairs(lines) do
        table.insert(numbered, string.format("%d: %s", i, line))
    end
    table.insert(parts, string.format(
        "Current file: %s (filetype: %s)\n\n%s",
        filename, ft, table.concat(numbered, "\n")
    ))

    -- Diff regions
    local region_strs = {}
    for _, r in ipairs(diff_regions) do
        table.insert(region_strs, string.format("lines %d-%d", r[1], r[2]))
    end
    table.insert(parts, "Changed regions (diff): " .. table.concat(region_strs, ", "))

    return table.concat(parts, "\n\n")
end

--- Parse the LLM response into a list of modifications.
--- @param response string
--- @return table[]|nil modifications, string|nil error
local function parse_response(response)
    -- Extract JSON array from response (handle potential markdown fences)
    local json_str = response:match("%[.-%]")
    if not json_str then
        -- Could be an empty response or malformed
        if response:match("^%s*$") then
            return {}, nil
        end
        return nil, "Could not find JSON array in response"
    end

    local ok, result = pcall(vim.fn.json_decode, json_str)
    if not ok then
        return nil, "Failed to parse JSON: " .. tostring(result)
    end

    if type(result) ~= "table" then
        return nil, "Expected JSON array, got " .. type(result)
    end

    -- Validate each modification
    local mods = {}
    for _, item in ipairs(result) do
        if type(item) == "table"
            and type(item.start_line) == "number"
            and type(item.end_line) == "number"
            and type(item.replacement) == "string"
            and type(item.comment) == "string"
        then
            table.insert(mods, {
                start_line = item.start_line,
                end_line = item.end_line,
                replacement = item.replacement,
                comment = item.comment,
            })
        end
    end

    return mods, nil
end

--- Filter modifications to only those within diff regions.
--- @param mods table[]
--- @param regions table[]
--- @return table[] filtered
local function filter_to_diff(mods, regions)
    local filtered = {}
    for _, mod in ipairs(mods) do
        if is_within_diff(mod.start_line, mod.end_line, regions) then
            table.insert(filtered, mod)
        else
            debug.log(string.format(
                "Lag: rejected modification at lines %d-%d (outside diff regions)",
                mod.start_line, mod.end_line
            ))
        end
    end
    return filtered
end

--- Apply modifications to the buffer. Processes in reverse line order to keep
--- line numbers stable. Stores original code for revert.
--- @param bufnr number
--- @param mods table[]
local function apply_modifications(bufnr, mods)
    local state = buffers[bufnr]
    if not state then return end

    -- Sort by start_line descending so replacements don't shift later lines
    table.sort(mods, function(a, b) return a.start_line > b.start_line end)

    state.modifications = {}

    for _, mod in ipairs(mods) do
        local start_0 = mod.start_line - 1
        local end_0 = mod.end_line

        -- Save original lines for revert
        local original_lines = vim.api.nvim_buf_get_lines(bufnr, start_0, end_0, false)

        -- Split replacement into lines
        local new_lines = vim.split(mod.replacement, "\n", { plain = true })

        -- Re-indent: match the indentation of the first original line
        if #original_lines > 0 then
            local target_indent = get_indent(original_lines[1])
            for i, line in ipairs(new_lines) do
                -- Strip existing indentation, apply target
                local stripped = line:gsub("^%s*", "")
                if stripped ~= "" then
                    -- For first line use target indent, for subsequent lines
                    -- preserve relative indent from the replacement
                    if i == 1 then
                        new_lines[i] = target_indent .. stripped
                    else
                        -- Calculate relative indent from first replacement line
                        local first_indent = get_indent(vim.split(mod.replacement, "\n", { plain = true })[1])
                        local this_indent = get_indent(line)
                        local relative = ""
                        if #this_indent > #first_indent then
                            relative = this_indent:sub(#first_indent + 1)
                        end
                        new_lines[i] = target_indent .. relative .. stripped
                    end
                else
                    new_lines[i] = ""
                end
            end
        end

        -- Apply the replacement
        vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, new_lines)

        -- Store modification info (line now refers to where the comment goes)
        -- After replacement, the modification starts at start_line
        table.insert(state.modifications, 1, {
            line = mod.start_line,
            comment = mod.comment,
            original_lines = original_lines,
            new_lines = new_lines,
            original_start = mod.start_line,
            original_end = mod.end_line,
        })
    end

    -- Update the baseline to include AI changes (so they don't show as user diffs)
    state.baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Set active to nearest cursor
    update_active(bufnr)
    render_modifications(bufnr)
end

--- Revert the active modification.
--- @param bufnr number
--- @return boolean reverted
local function revert_active(bufnr)
    local state = buffers[bufnr]
    if not state or #state.modifications == 0 or not state.active_index then
        return false
    end

    local idx = state.active_index
    local mod = state.modifications[idx]

    -- Calculate current position: we need to figure out where this modification
    -- is now. Line numbers may have shifted due to previous reverts.
    -- We use the stored line as the anchor.
    local start_0 = mod.line - 1
    local end_0 = start_0 + #mod.new_lines

    -- Replace new lines with original
    vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, mod.original_lines)

    -- Update the baseline to include the revert (reverts are not diffs)
    state.baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Remove this modification
    table.remove(state.modifications, idx)

    -- Adjust line numbers for modifications below this one
    local line_delta = #mod.original_lines - #mod.new_lines
    for _, m in ipairs(state.modifications) do
        if m.line > mod.line then
            m.line = m.line + line_delta
        end
    end

    -- Update active index
    if #state.modifications == 0 then
        state.active_index = nil
        clear_modification_extmarks(bufnr)
    else
        state.active_index = nil -- Force re-calculation
        update_active(bufnr)
        render_modifications(bufnr)
    end

    return true
end

--- Clear all modifications from a buffer without reverting.
--- @param bufnr number
local function clear_modifications(bufnr)
    local state = buffers[bufnr]
    if not state then return end

    state.modifications = {}
    state.active_index = nil
    clear_modification_extmarks(bufnr)
end

--- Process a buffer save: diff, send to LLM, apply modifications.
--- @param bufnr number
--- @param get_context fun(): string|nil
--- @param get_session fun(): table
local function on_save(bufnr, get_context, get_session)
    local state = buffers[bufnr]
    if not state then return end
    if state.processing then
        debug.log("Lag: skipping save, already processing buffer " .. bufnr)
        return
    end

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local diff_regions = compute_diff_regions(state.baseline, current_lines)

    if #diff_regions == 0 then
        debug.log("Lag: no diff regions, skipping buffer " .. bufnr)
        return
    end

    -- Skip if all changed lines are whitespace-only
    local has_content = false
    for _, region in ipairs(diff_regions) do
        for l = region[1], region[2] do
            if current_lines[l] and not current_lines[l]:match("^%s*$") then
                has_content = true
                break
            end
        end
        if has_content then break end
    end
    if not has_content then
        debug.log("Lag: diff is whitespace-only, skipping buffer " .. bufnr)
        state.baseline = current_lines
        return
    end

    debug.log(string.format("Lag: %d diff region(s) in buffer %d", #diff_regions, bufnr))

    -- Clear previous modifications before processing new ones
    clear_modifications(bufnr)

    state.processing = true

    -- Show working indicator on diff regions
    show_working_indicator(bufnr, diff_regions)
    vim.cmd("redraw")

    -- Snapshot diff regions and current lines so they can't be mutated
    local snapshot_regions = vim.deepcopy(diff_regions)
    local context_block = get_context()
    local session = get_session()

    local prompt = build_lag_prompt(bufnr, snapshot_regions, context_block, session)
    local response_chunks = {}

    api.stream(
        { { role = "user", content = prompt } },
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)
        end,
        -- on_done
        function()
            state.processing = false
            clear_working_indicator(bufnr)

            local full_response = table.concat(response_chunks, "")
            debug.log("Lag: LLM response:\n" .. full_response)

            local mods, err = parse_response(full_response)
            if err then
                debug.log("Lag: parse error: " .. err)
                vim.cmd("redraw")
                return
            end

            if #mods == 0 then
                debug.log("Lag: no modifications suggested")
                vim.cmd("redraw")
                return
            end

            -- Filter to only modifications within diff regions
            mods = filter_to_diff(mods, snapshot_regions)
            if #mods == 0 then
                debug.log("Lag: all modifications were outside diff regions")
                vim.cmd("redraw")
                return
            end

            debug.log(string.format("Lag: applying %d modification(s)", #mods))
            apply_modifications(bufnr, mods)
            vim.cmd("redraw")
        end,
        -- on_error
        function(err)
            state.processing = false
            clear_working_indicator(bufnr)
            debug.log("Lag: stream error: " .. err)
            vim.cmd("redraw")
        end,
        { system_prompt = build_system_prompt() }
    )
end

--- Start lag mode for the current buffer.
--- @param get_context fun(): string|nil  Function to get context block
--- @param get_session fun(): table  Function to get current session
function M.start(get_context, get_session)
    local bufnr = vim.api.nvim_get_current_buf()

    if buffers[bufnr] then
        vim.notify("Lag: already active for this buffer", vim.log.levels.WARN)
        return
    end

    setup_highlights()

    local ns = vim.api.nvim_create_namespace("ai_lag_" .. bufnr)

    buffers[bufnr] = {
        baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        processing = false,
        debounce_timer = nil,
        autocmd_ids = {},
        modifications = {},
        ns = ns,
        active_index = nil,
        working_extmarks = {},
    }

    local state = buffers[bufnr]

    -- BufWritePost: debounced trigger
    local write_id = vim.api.nvim_create_autocmd("BufWritePost", {
        buffer = bufnr,
        callback = function()
            -- Debounce
            if state.debounce_timer then
                state.debounce_timer:stop()
                state.debounce_timer:close()
                state.debounce_timer = nil
            end
            local timer = vim.uv.new_timer()
            state.debounce_timer = timer
            timer:start(lag_config.debounce_ms, 0, vim.schedule_wrap(function()
                if timer then
                    timer:stop()
                    timer:close()
                end
                if state.debounce_timer == timer then
                    state.debounce_timer = nil
                end
                on_save(bufnr, get_context, get_session)
            end))
        end,
    })
    table.insert(state.autocmd_ids, write_id)

    -- CursorMoved: update active modification
    local cursor_id = vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = bufnr,
        callback = function()
            update_active(bufnr)
        end,
    })
    table.insert(state.autocmd_ids, cursor_id)

    debug.log("Lag: started for buffer " .. bufnr)
    vim.notify("Lag: started")
end

--- Stop lag mode for the current buffer.
function M.stop()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: not active for this buffer", vim.log.levels.WARN)
        return
    end

    -- Clean up timer
    if state.debounce_timer then
        state.debounce_timer:stop()
        state.debounce_timer:close()
        state.debounce_timer = nil
    end

    -- Remove autocmds
    for _, id in ipairs(state.autocmd_ids) do
        pcall(vim.api.nvim_del_autocmd, id)
    end

    -- Clear all visual indicators
    clear_modification_extmarks(bufnr)
    clear_working_indicator(bufnr)
    vim.diagnostic.reset(ns_diagnostic, bufnr)

    buffers[bufnr] = nil

    debug.log("Lag: stopped for buffer " .. bufnr)
    vim.notify("Lag: stopped")
end

--- Revert the active modification in the current buffer.
function M.revert()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: not active for this buffer", vim.log.levels.WARN)
        return
    end

    if #state.modifications == 0 then
        vim.notify("Lag: no modifications to revert", vim.log.levels.INFO)
        return
    end

    if revert_active(bufnr) then
        vim.cmd("redraw")
        vim.notify("Lag: reverted modification")
    end
end

--- Clear all modifications in the current buffer (without reverting).
function M.clear()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: not active for this buffer", vim.log.levels.WARN)
        return
    end

    clear_modifications(bufnr)
    vim.cmd("redraw")
    vim.notify("Lag: cleared all modifications")
end

--- Reset all lag state (for testing).
function M.reset()
    for bufnr, state in pairs(buffers) do
        if state.debounce_timer then
            state.debounce_timer:stop()
            state.debounce_timer:close()
        end
        for _, id in ipairs(state.autocmd_ids) do
            pcall(vim.api.nvim_del_autocmd, id)
        end
        pcall(clear_modification_extmarks, bufnr)
        pcall(clear_working_indicator, bufnr)
        pcall(vim.diagnostic.reset, ns_diagnostic, bufnr)
    end
    buffers = {}
end

--- Check if lag mode is active for a buffer.
--- @param bufnr number|nil defaults to current buffer
--- @return boolean
function M.is_active(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return buffers[bufnr] ~= nil
end

--- Get the state for a buffer (for testing).
--- @param bufnr number|nil
--- @return table|nil
function M.get_state(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return buffers[bufnr]
end

-- Expose internals for testing
M._compute_diff_regions = compute_diff_regions
M._is_within_diff = is_within_diff
M._parse_response = parse_response
M._filter_to_diff = filter_to_diff
M._on_save = on_save
M._apply_modifications = apply_modifications
M._revert_active = revert_active
M._clear_modifications = clear_modifications
M._update_active = update_active
M._render_modifications = render_modifications

return M
