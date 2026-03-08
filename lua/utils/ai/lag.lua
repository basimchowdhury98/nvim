-- lag.lua
-- AI Lag Mode: watches buffer saves globally, diffs changes, sends to LLM for
-- automatic fixes/implementations within the changed regions.

local api = require("utils.ai.api")
local debug = require("utils.ai.debug")
local usage = require("utils.ai.usage")
local M = {}

-- Global state
local running = false
local autocmd_ids = {}
local get_context_fn = nil
local get_session_fn = nil

-- Per-buffer state keyed by bufnr
-- Each entry: {
--   baseline = string[],       -- buffer snapshot at last user-initiated save
--   processing = bool,         -- LLM call in flight for this buffer
--   pending_save = bool,       -- save queued while processing
--   queue_count = number,      -- number of queued saves waiting
--   modifications = table[],   -- applied modifications with original code for revert
--   ns = number,               -- extmark namespace for this buffer
--   active_index = number|nil, -- index of nearest modification to cursor
--   working_extmarks = table,  -- extmark ids for "working..." indicators
-- }
local buffers = {}


-- Namespace for working indicators (shared)
local ns_working = vim.api.nvim_create_namespace("ai_lag_working")

-- Define highlight groups by linking to standard groups (adapts to any colorscheme)
local function setup_highlights()
    local set = vim.api.nvim_set_hl
    set(0, "AILagComment", { link = "Comment", default = true })
    set(0, "AILagActiveComment", { link = "Title", default = true })
    set(0, "AILagWorking", { link = "Comment", default = true })
    set(0, "AILagWorkingLine", { link = "CursorLine", default = true })
    set(0, "AILagLine", { link = "DiffAdd", default = true })
    set(0, "AILagActiveLine", { link = "Visual", default = true })
end

--- Get or create per-buffer state.
--- @param bufnr number
--- @return table
local function get_or_create_state(bufnr)
    if not buffers[bufnr] then
        buffers[bufnr] = {
            baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
            processing = false,
            pending_save = false,
            queue_count = 0,
            modifications = {},
            ns = vim.api.nvim_create_namespace("ai_lag_" .. bufnr),
            active_index = nil,
            working_extmarks = {},
            cancel_request = nil,
            cancelled = false,
            fidget_handle = nil,
        }
    end
    return buffers[bufnr]
end

--- Compute a unified diff between two line arrays.
--- Returns a list of changed regions: { { start_line, end_line } }
--- Lines are 1-indexed and refer to positions in `new_lines`.
--- @param old_lines string[]
--- @param new_lines string[]
--- @return table[] regions
local function compute_diff_regions(old_lines, new_lines)
    local old_text = table.concat(old_lines, "\n") .. "\n"
    local new_text = table.concat(new_lines, "\n") .. "\n"

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
        local new_start = hunk[3]
        local new_count = hunk[4]
        if new_count > 0 then
            table.insert(regions, { new_start, new_start + new_count - 1 })
        elseif new_count == 0 and new_start > 0 then
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

--- Get the wrap width from colorcolumn (first value), falling back to window width.
--- @return number
local function get_wrap_width()
    local cc = vim.opt.colorcolumn:get()
    if cc and #cc > 0 then
        local first = tonumber(cc[1])
        if first and first > 0 then return first end
    end
    return vim.api.nvim_win_get_width(0)
end

--- Wrap text into multiple lines that fit within a given width.
--- The first line accounts for a prefix (e.g. indent + "Lag: "),
--- continuation lines are indented to align with the first line's text.
--- @param prefix string  the leading text (indent + "Lag: ")
--- @param text string    the comment to wrap
--- @param width number   the target column width
--- @return string[]      list of lines (first includes prefix)
local function wrap_comment(prefix, text, width)
    local first_budget = width - #prefix
    if first_budget <= 0 then first_budget = width end

    -- continuation lines get same indent + spaces to align past "Lag: "
    local cont_prefix = prefix:match("^(%s*)") or ""
    cont_prefix = cont_prefix .. string.rep(" ", #prefix - #cont_prefix)
    local cont_budget = width - #cont_prefix
    if cont_budget <= 0 then cont_budget = width end

    local lines = {}
    local remaining = text

    -- first line
    if #remaining <= first_budget then
        table.insert(lines, prefix .. remaining)
        return lines
    end

    -- find last space within budget, or force-break
    local break_at = first_budget
    local space_pos = remaining:sub(1, first_budget):find("%s[^%s]*$")
    if space_pos then break_at = space_pos - 1 end

    table.insert(lines, prefix .. remaining:sub(1, break_at))
    remaining = remaining:sub(break_at + 1):gsub("^%s+", "")

    -- continuation lines
    while #remaining > 0 do
        if #remaining <= cont_budget then
            table.insert(lines, cont_prefix .. remaining)
            break
        end

        break_at = cont_budget
        space_pos = remaining:sub(1, cont_budget):find("%s[^%s]*$")
        if space_pos then break_at = space_pos - 1 end

        table.insert(lines, cont_prefix .. remaining:sub(1, break_at))
        remaining = remaining:sub(break_at + 1):gsub("^%s+", "")
    end

    return lines
end

--- Scroll the viewport to reveal virt_lines_above on row 0 if needed.
--- @param bufnr number
--- @param virt_line_count number  how many virtual lines are above row 0
local function reveal_top_virtual_lines(bufnr, virt_line_count)
    if virt_line_count <= 0 then return end
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        local view = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview() end)
        if view.topline == 1 then
            vim.api.nvim_win_call(win, function()
                vim.fn.winrestview({ topline = 1, topfill = virt_line_count })
            end)
        end
    end
end

--- Place "LAG: working..." virtual text and line highlights over diff regions.
--- @param bufnr number
--- @param regions table[] diff regions (1-indexed)
local function show_working_indicator(bufnr, regions)
    local state = buffers[bufnr]
    if not state then return end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for _, region in ipairs(regions) do
        local start_line = region[1] - 1
        local end_line = region[2] - 1

        if start_line >= 0 and start_line < line_count then
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)[1] or ""
            local indent = get_indent(buf_line)
            local id = vim.api.nvim_buf_set_extmark(bufnr, ns_working, start_line, 0, {
                virt_lines_above = true,
                virt_lines = { { { indent .. "Lag: working...", "AILagWorking" } } },
            })
            table.insert(state.working_extmarks, id)
        end

        for l = start_line, math.min(end_line, line_count - 1) do
            local id = vim.api.nvim_buf_set_extmark(bufnr, ns_working, l, 0, {
                line_hl_group = "AILagWorkingLine",
            })
            table.insert(state.working_extmarks, id)
        end
    end

    -- If any region starts at line 1, scroll to reveal the virtual line above row 0
    for _, region in ipairs(regions) do
        if region[1] == 1 then
            reveal_top_virtual_lines(bufnr, 1)
            break
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

--- Render virtual text comments, line highlights, and hidden info for all modifications.
--- @param bufnr number
local function render_modifications(bufnr)
    local state = buffers[bufnr]
    if not state then return end

    clear_modification_extmarks(bufnr)

    if #state.modifications == 0 then return end

    for i, mod in ipairs(state.modifications) do
        local line = mod.line - 1
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line >= 0 and line < line_count then
            local is_active = (i == state.active_index)
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
            local indent = get_indent(buf_line)
            local comment_hl = is_active and "AILagActiveComment" or "AILagComment"
            local line_hl = is_active and "AILagActiveLine" or "AILagLine"

            local prefix = indent .. "Lag: "
            local wrapped = wrap_comment(prefix, mod.comment, get_wrap_width())
            local virt_lines = {}
            for _, vl in ipairs(wrapped) do
                table.insert(virt_lines, { { vl, comment_hl } })
            end
            vim.api.nvim_buf_set_extmark(bufnr, state.ns, line, 0, {
                virt_lines_above = true,
                virt_lines = virt_lines,
            })

            local end_line = math.min(line + #mod.new_lines, line_count)
            for l = line, end_line - 1 do
                vim.api.nvim_buf_set_extmark(bufnr, state.ns, l, 0, {
                    line_hl_group = line_hl,
                })
            end

            vim.api.nvim_buf_set_extmark(bufnr, state.ns, end_line - 1, 0, {
                virt_text = { { "── " .. format_old_code(mod.original_lines), "Comment" } },
                virt_text_hide = true,
                virt_text_pos = "eol",
            })
        end
    end

    -- If any modification is on line 1, scroll to reveal virtual lines above row 0
    for _, mod in ipairs(state.modifications) do
        if mod.line == 1 then
            local prefix = get_indent(
                (vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or "")
            ) .. "Lag: "
            local virt_count = #wrap_comment(prefix, mod.comment, get_wrap_width())
            reveal_top_virtual_lines(bufnr, virt_count)
            break
        end
    end
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

--- Prune modifications whose lines have been edited by the user.
--- A modification is pruned if the buffer lines at its range no longer match
--- the stored new_lines.
--- @param bufnr number
local function prune_edited_modifications(bufnr)
    local state = buffers[bufnr]
    if not state or #state.modifications == 0 then return end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local pruned = false
    local kept = {}

    for _, mod in ipairs(state.modifications) do
        local start_0 = mod.line - 1
        local end_0 = start_0 + #mod.new_lines
        local still_matches = true

        if end_0 > line_count then
            still_matches = false
        else
            local current = vim.api.nvim_buf_get_lines(bufnr, start_0, end_0, false)
            if #current ~= #mod.new_lines then
                still_matches = false
            else
                for i, line in ipairs(current) do
                    if line ~= mod.new_lines[i] then
                        still_matches = false
                        break
                    end
                end
            end
        end

        if still_matches then
            table.insert(kept, mod)
        else
            pruned = true
            debug.log(string.format("Lag: pruned modification at line %d (user edited)", mod.line))
        end
    end

    if pruned then
        state.modifications = kept
        state.active_index = nil
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

    if context_block then
        table.insert(parts, context_block)
    end

    if session and #session.conversation > 0 then
        table.insert(parts, "Recent chat history for context:")
        for _, msg in ipairs(session.conversation) do
            table.insert(parts, string.format("[%s]: %s", msg.role, msg.content))
        end
    end

    local numbered = {}
    for i, line in ipairs(lines) do
        table.insert(numbered, string.format("%d: %s", i, line))
    end
    table.insert(parts, string.format(
        "Current file: %s (filetype: %s)\n\n%s",
        filename, ft, table.concat(numbered, "\n")
    ))

    local region_strs = {}
    for _, r in ipairs(diff_regions) do
        table.insert(region_strs, string.format("lines %d-%d", r[1], r[2]))
    end
    table.insert(parts, "Changed regions (diff): " .. table.concat(region_strs, ", "))

    return table.concat(parts, "\n\n")
end

--- Find the JSON array by tracking bracket depth and ignoring brackets inside strings.
--- @param response string
--- @return string|nil json_str
local function extract_json_array(response)
    local start_idx = response:find("%[")
    if not start_idx then
        return nil
    end

    local depth = 0
    local in_string = false
    local string_char = nil

    for i = start_idx, #response do
        local c = response:sub(i, i)

        if in_string then
            if c == string_char and response:sub(i - 1, i - 1) ~= "\\" then
                in_string = false
            end
        else
            if c == '"' or c == "'" then
                in_string = true
                string_char = c
            elseif c == "[" then
                depth = depth + 1
            elseif c == "]" then
                depth = depth - 1
                if depth == 0 then
                    return response:sub(start_idx, i)
                end
            end
        end
    end

    return nil
end

--- Parse the LLM response into a list of modifications.
--- @param response string
--- @return table[]|nil modifications, string|nil error
local function parse_response(response)
    local json_str = extract_json_array(response)
    if not json_str then
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
--- line numbers stable. Appends to existing modifications list.
--- @param bufnr number
--- @param mods table[]
local function apply_modifications(bufnr, mods)
    local state = buffers[bufnr]
    if not state then return end

    table.sort(mods, function(a, b) return a.start_line > b.start_line end)

    -- Adjust existing modification line numbers for insertions/deletions
    -- that happen above them (applied in reverse order, so we track cumulative shift)
    local new_mods = {}

    for _, mod in ipairs(mods) do
        local start_0 = mod.start_line - 1
        local end_0 = mod.end_line

        local original_lines = vim.api.nvim_buf_get_lines(bufnr, start_0, end_0, false)

        local new_lines = vim.split(mod.replacement, "\n", { plain = true })

        if #original_lines > 0 then
            local target_indent = get_indent(original_lines[1])
            for i, line in ipairs(new_lines) do
                local stripped = line:gsub("^%s*", "")
                if stripped ~= "" then
                    if i == 1 then
                        new_lines[i] = target_indent .. stripped
                    else
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

        vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, new_lines)

        local line_delta = #new_lines - #original_lines
        -- Shift existing modifications that are below this insertion point
        for _, existing in ipairs(state.modifications) do
            if existing.line > mod.start_line then
                existing.line = existing.line + line_delta
            end
        end
        -- Also shift already-processed new mods
        for _, nm in ipairs(new_mods) do
            if nm.line > mod.start_line then
                nm.line = nm.line + line_delta
            end
        end

        table.insert(new_mods, 1, {
            line = mod.start_line,
            comment = mod.comment,
            original_lines = original_lines,
            new_lines = new_lines,
            original_start = mod.start_line,
            original_end = mod.end_line,
        })
    end

    -- Append new modifications to existing list
    for _, nm in ipairs(new_mods) do
        table.insert(state.modifications, nm)
    end

    -- Update the baseline to include AI changes
    state.baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

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

    local start_0 = mod.line - 1
    local end_0 = start_0 + #mod.new_lines

    vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, mod.original_lines)

    state.baseline = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    table.remove(state.modifications, idx)

    local line_delta = #mod.original_lines - #mod.new_lines
    for _, m in ipairs(state.modifications) do
        if m.line > mod.line then
            m.line = m.line + line_delta
        end
    end

    if #state.modifications == 0 then
        state.active_index = nil
        clear_modification_extmarks(bufnr)
    else
        state.active_index = nil
        update_active(bufnr)
        render_modifications(bufnr)
    end

    return true
end

--- Accept the active modification (keep code, remove decorations).
--- @param bufnr number
--- @return boolean accepted
local function accept_active(bufnr)
    local state = buffers[bufnr]
    if not state or #state.modifications == 0 or not state.active_index then
        return false
    end

    local idx = state.active_index
    table.remove(state.modifications, idx)

    if #state.modifications == 0 then
        state.active_index = nil
        clear_modification_extmarks(bufnr)
    else
        state.active_index = nil
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

-- Forward declaration
local on_save

--- Process the queue: if a save is pending, re-trigger on_save.
--- @param bufnr number
local function process_queue(bufnr)
    local state = buffers[bufnr]
    if not state then return end

    if state.pending_save then
        state.pending_save = false
        on_save(bufnr)
    end
end

--- Process a buffer save: diff, send to LLM, apply modifications.
--- @param bufnr number
on_save = function(bufnr)
    local state = get_or_create_state(bufnr)

    if state.processing then
        state.pending_save = true
        state.queue_count = state.queue_count + 1
        debug.log("Lag: queued save for buffer " .. bufnr .. " (" .. state.queue_count .. " queued)")
        return
    end

    -- Prune modifications the user has edited
    prune_edited_modifications(bufnr)

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local diff_regions = compute_diff_regions(state.baseline, current_lines)

    if #diff_regions == 0 then
        debug.log("Lag: no diff regions, skipping buffer " .. bufnr)
        return
    end

    -- Filter out whitespace-only diff regions
    local meaningful_regions = {}
    for _, region in ipairs(diff_regions) do
        local has_content = false
        for l = region[1], region[2] do
            if current_lines[l] and not current_lines[l]:match("^%s*$") then
                has_content = true
                break
            end
        end
        if has_content then
            table.insert(meaningful_regions, region)
        end
    end
    if #meaningful_regions == 0 then
        debug.log("Lag: all diff regions are whitespace-only, skipping buffer " .. bufnr)
        state.baseline = current_lines
        return
    end
    diff_regions = meaningful_regions

    debug.log(string.format("Lag: %d diff region(s) in buffer %d", #diff_regions, bufnr))

    state.processing = true
    state.cancelled = false
    state.queue_count = 0

    show_working_indicator(bufnr, diff_regions)

    -- Fidget progress spinner with queue count
    local f_ok, progress = pcall(require, "fidget.progress")
    state.fidget_handle = nil
    if f_ok then
        state.fidget_handle = progress.handle.create({
            title = "Lag",
            message = "Reviewing...",
            lsp_client = { name = "Lag" },
        })
    end

    vim.cmd("redraw")

    local snapshot_regions = vim.deepcopy(diff_regions)
    local snapshot_lines = vim.deepcopy(current_lines)
    local context_block = get_context_fn and get_context_fn() or nil
    local session = get_session_fn and get_session_fn() or { conversation = {} }

    local prompt = build_lag_prompt(bufnr, snapshot_regions, context_block, session)
    local response_chunks = {}

    state.cancel_request = api.stream(
        { { role = "user", content = prompt } },
        function(delta)
            table.insert(response_chunks, delta)
            -- Update fidget with queue count if saves came in
            if state.fidget_handle and state.queue_count > 0 then
                state.fidget_handle.message = "Reviewing... (" .. state.queue_count .. " queued)"
            end
        end,
        function(metadata)
            state.cancel_request = nil
            if state.cancelled then
                return
            end
            state.processing = false
            clear_working_indicator(bufnr)
            if state.fidget_handle then
                state.fidget_handle.message = "Done"
                state.fidget_handle:finish()
                state.fidget_handle = nil
            end
            usage.add(metadata)

            local full_response = table.concat(response_chunks, "")
            debug.log("Lag: LLM response:\n" .. full_response)

            local mods, err = parse_response(full_response)
            if err then
                debug.log("Lag: parse error: " .. err)
                state.baseline = snapshot_lines
                vim.cmd("redraw")
                process_queue(bufnr)
                return
            end

            if #mods == 0 then
                debug.log("Lag: no modifications suggested")
                state.baseline = snapshot_lines
                vim.cmd("redraw")
                process_queue(bufnr)
                return
            end

            mods = filter_to_diff(mods, snapshot_regions)
            if #mods == 0 then
                debug.log("Lag: all modifications were outside diff regions")
                state.baseline = snapshot_lines
                vim.cmd("redraw")
                process_queue(bufnr)
                return
            end

            debug.log(string.format("Lag: applying %d modification(s)", #mods))
            apply_modifications(bufnr, mods)
            vim.cmd("redraw")
            process_queue(bufnr)
        end,
        function(err)
            state.cancel_request = nil
            if state.cancelled then
                return
            end
            state.processing = false
            clear_working_indicator(bufnr)
            if state.fidget_handle then
                state.fidget_handle.message = "Error"
                state.fidget_handle:finish()
                state.fidget_handle = nil
            end
            debug.log("Lag: stream error: " .. err)
            vim.cmd("redraw")
            process_queue(bufnr)
        end,
        { system_prompt = build_system_prompt(), source = "lag" }
    )
end

--- Start lag mode globally.
--- @param get_context fun(): string|nil
--- @param get_session fun(): table
function M.start(get_context, get_session)
    if running then
        vim.notify("Lag: already running", vim.log.levels.WARN)
        return
    end

    setup_highlights()

    get_context_fn = get_context
    get_session_fn = get_session
    running = true

    -- Global BufWritePost: triggers on any buffer save
    local write_id = vim.api.nvim_create_autocmd("BufWritePost", {
        callback = function(ev)
            local bufnr = ev.buf
            -- Skip special buffers
            local bt = vim.bo[bufnr].buftype
            if bt ~= "" then return end
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == "" then return end

            get_or_create_state(bufnr)
            on_save(bufnr)
        end,
    })
    table.insert(autocmd_ids, write_id)

    -- BufEnter: capture baseline when visiting a buffer (before user edits)
    local enter_id = vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(ev)
            local bufnr = ev.buf
            local bt = vim.bo[bufnr].buftype
            if bt ~= "" then return end
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == "" then return end
            get_or_create_state(bufnr)
        end,
    })
    table.insert(autocmd_ids, enter_id)

    -- Eagerly capture baseline for the current buffer
    local cur = vim.api.nvim_get_current_buf()
    if vim.bo[cur].buftype == "" and vim.api.nvim_buf_get_name(cur) ~= "" then
        get_or_create_state(cur)
    end

    -- Global CursorMoved: update active modification
    local cursor_id = vim.api.nvim_create_autocmd("CursorMoved", {
        callback = function(ev)
            local bufnr = ev.buf
            if buffers[bufnr] then
                update_active(bufnr)
            end
        end,
    })
    table.insert(autocmd_ids, cursor_id)

    debug.log("Lag: started globally")
    vim.notify("Lag: started")
end

--- Tear down all lag state: autocmds, buffer visuals, per-buffer data, callbacks.
local function teardown()
    for _, id in ipairs(autocmd_ids) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    autocmd_ids = {}

    for bufnr, _ in pairs(buffers) do
        pcall(clear_modification_extmarks, bufnr)
        pcall(clear_working_indicator, bufnr)
    end
    buffers = {}

    get_context_fn = nil
    get_session_fn = nil
    running = false
end

--- Cancel all in-flight and queued lag requests without stopping lag mode.
--- Preserves baseline (so diff regions are picked up again on next save),
--- existing modifications, and autocmds.
function M.cancel()
    if not running then
        return false
    end

    local cancelled_any = false
    for bufnr, state in pairs(buffers) do
        if state.processing then
            state.cancelled = true
            state.processing = false
            state.pending_save = false
            state.queue_count = 0

            if state.cancel_request then
                state.cancel_request()
                state.cancel_request = nil
            end

            clear_working_indicator(bufnr)

            if state.fidget_handle then
                state.fidget_handle.message = "Cancelled"
                state.fidget_handle:finish()
                state.fidget_handle = nil
            end

            cancelled_any = true
            debug.log("Lag: cancelled in-flight request for buffer " .. bufnr)
        elseif state.pending_save then
            state.pending_save = false
            state.queue_count = 0
            cancelled_any = true
            debug.log("Lag: cleared queued save for buffer " .. bufnr)
        end
    end

    return cancelled_any
end

--- Stop lag mode globally.
function M.stop()
    if not running then
        vim.notify("Lag: not running", vim.log.levels.WARN)
        return
    end

    teardown()
    debug.log("Lag: stopped")
    vim.notify("Lag: stopped")
end

--- Toggle lag mode on/off.
--- @param get_context function  context builder (required when starting)
--- @param get_session function  session accessor (required when starting)
function M.toggle(get_context, get_session)
    if running then
        M.stop()
    else
        M.start(get_context, get_session)
    end
    require("utils.ai.usage").update_tabline()
end

--- Revert the active modification in the current buffer.
function M.revert()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: no modifications in this buffer", vim.log.levels.INFO)
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

--- Accept the active modification in the current buffer (keep code, clear decorations).
function M.accept()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: no modifications in this buffer", vim.log.levels.INFO)
        return
    end

    if #state.modifications == 0 then
        vim.notify("Lag: no modifications to accept", vim.log.levels.INFO)
        return
    end

    if accept_active(bufnr) then
        vim.cmd("redraw")
        vim.notify("Lag: accepted modification")
    end
end

--- Accept all modifications in the current buffer (keep code, clear all decorations).
function M.clear()
    local bufnr = vim.api.nvim_get_current_buf()
    local state = buffers[bufnr]

    if not state then
        vim.notify("Lag: no modifications in this buffer", vim.log.levels.INFO)
        return
    end

    clear_modifications(bufnr)
    vim.cmd("redraw")
    vim.notify("Lag: accepted all modifications")
end

--- Reset all lag state (for testing).
function M.reset()
    teardown()
end

--- Check if lag mode is running globally.
--- @return boolean
function M.is_running()
    return running
end

--- Get a snapshot of all lag state for diagnostics.
--- @return table
function M.get_all_state()
    local buf_states = {}
    for bufnr, state in pairs(buffers) do
        local name = vim.api.nvim_buf_is_valid(bufnr)
            and vim.api.nvim_buf_get_name(bufnr) or ("invalid:" .. bufnr)
        local mods = {}
        for i, mod in ipairs(state.modifications) do
            mods[i] = {
                line = mod.line,
                original_start = mod.original_start,
                original_end = mod.original_end,
                new_lines = mod.new_lines,
                original_lines = mod.original_lines,
            }
        end
        buf_states[name] = {
            baseline_lines = #state.baseline,
            processing = state.processing,
            pending_save = state.pending_save,
            queue_count = state.queue_count,
            active_index = state.active_index,
            modifications = mods,
        }
    end
    return {
        running = running,
        buffers = buf_states,
    }
end

--- Populate the quickfix list with all pending lag modifications across buffers.
function M.quickfix()
    local items = {}
    for bufnr, state in pairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) and #state.modifications > 0 then
            local filename = vim.api.nvim_buf_get_name(bufnr)
            for _, mod in ipairs(state.modifications) do
                table.insert(items, {
                    filename = filename,
                    lnum = mod.line,
                    text = "Lag: " .. mod.comment,
                })
            end
        end
    end

    if #items == 0 then
        vim.notify("Lag: no pending modifications", vim.log.levels.INFO)
        return
    end

    table.sort(items, function(a, b)
        if a.filename ~= b.filename then return a.filename < b.filename end
        return a.lnum < b.lnum
    end)

    vim.fn.setqflist({}, " ", { title = "Lag: pending modifications", items = items })
    vim.cmd("copen")
end

--- Count total pending modifications across all buffers.
--- @return number
function M.pending_count()
    local count = 0
    for bufnr, state in pairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            count = count + #state.modifications
        end
    end
    return count
end

--- Check if a buffer has lag state.
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
M._accept_active = accept_active
M._clear_modifications = clear_modifications
M._update_active = update_active
M._render_modifications = render_modifications
M._prune_edited_modifications = prune_edited_modifications
M._get_or_create_state = get_or_create_state
M._process_queue = process_queue

return M
