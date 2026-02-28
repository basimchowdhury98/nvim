local eq = assert.are.same
local lag = require("utils.ai.lag")
local api = require("utils.ai.api")

-- Stub response for the LLM
local stub_response = "[]"
local stub_error = nil
local stream_opts_spy = nil

local function stub_api()
    api.stream = function(_messages, on_delta, on_done, on_error, opts)
        stream_opts_spy = opts and vim.deepcopy(opts) or nil
        if stub_error then
            on_error(stub_error)
            return function() end
        end
        on_delta(stub_response)
        on_done()
        return function() end
    end
end

local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    local name = vim.fn.getcwd() .. "/lag_test_" .. buf .. ".lua"
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].filetype = "lua"
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

local function get_buf_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function noop_context()
    return nil
end

local function noop_session()
    return { conversation = {} }
end

describe("Lag Diff Computation", function()
    it("returns empty regions when lines are identical", function()
        local regions = lag._compute_diff_regions({ "a", "b", "c" }, { "a", "b", "c" })

        eq({}, regions, "Identical lines should produce no diff regions")
    end)

    it("detects a single changed line", function()
        local regions = lag._compute_diff_regions({ "a", "b", "c" }, { "a", "x", "c" })

        eq(1, #regions, "Should detect one changed region")
        eq(2, regions[1][1], "Region should start at line 2")
        eq(2, regions[1][2], "Region should end at line 2")
    end)

    it("detects added lines", function()
        local regions = lag._compute_diff_regions({ "a", "c" }, { "a", "b", "c" })

        eq(1, #regions, "Should detect one added region")
        assert(regions[1][1] <= 2 and regions[1][2] >= 2, "Region should cover the inserted line")
    end)

    it("detects multiple changed regions", function()
        local old = { "a", "b", "c", "d", "e" }
        local new = { "a", "X", "c", "Y", "e" }

        local regions = lag._compute_diff_regions(old, new)

        assert(#regions >= 1, "Should detect at least one changed region")
    end)

    it("returns empty regions for two empty buffers", function()
        local regions = lag._compute_diff_regions({ "" }, { "" })

        eq({}, regions, "Two empty buffers should produce no diff")
    end)
end)

describe("Lag Diff Boundary Enforcement", function()
    it("accepts modification within a diff region", function()
        local result = lag._is_within_diff(3, 5, { { 2, 6 } })

        eq(true, result, "Modification within region should be accepted")
    end)

    it("rejects modification outside all diff regions", function()
        local result = lag._is_within_diff(10, 12, { { 2, 6 } })

        eq(false, result, "Modification outside region should be rejected")
    end)

    it("accepts modification overlapping a diff region boundary", function()
        local result = lag._is_within_diff(5, 8, { { 3, 6 } })

        eq(true, result, "Overlapping modification should be accepted")
    end)

    it("accepts modification spanning exactly a diff region", function()
        local result = lag._is_within_diff(3, 6, { { 3, 6 } })

        eq(true, result, "Exact-span modification should be accepted")
    end)

    it("checks across multiple diff regions", function()
        local result = lag._is_within_diff(8, 9, { { 2, 4 }, { 7, 10 } })

        eq(true, result, "Modification in second region should be accepted")
    end)
end)

describe("Lag Response Parsing", function()
    it("parses a valid JSON response with one modification", function()
        local json = '[{"start_line": 2, "end_line": 3, "replacement": "fixed", "comment": "bug fix"}]'

        local mods, err = lag._parse_response(json)

        assert(err == nil, "Should not return an error")
        eq(1, #mods, "Should parse one modification")
        eq(2, mods[1].start_line, "Start line should be 2")
        eq("fixed", mods[1].replacement, "Replacement should match")
        eq("bug fix", mods[1].comment, "Comment should match")
    end)

    it("returns empty array for empty JSON array", function()
        local mods, err = lag._parse_response("[]")

        assert(err == nil, "Should not return an error")
        eq(0, #mods, "Should return empty modifications")
    end)

    it("returns error for non-JSON response", function()
        local mods, err = lag._parse_response("This is not JSON at all")

        assert(mods == nil, "Should return nil modifications")
        assert(err ~= nil, "Should return an error message")
    end)

    it("skips malformed items in the array", function()
        local json = '[{"start_line": 2, "end_line": 3, "replacement": "ok", "comment": "good"}, {"bad": true}]'

        local mods, err = lag._parse_response(json)

        assert(err == nil, "Should not return an error")
        eq(1, #mods, "Should only include valid modifications")
    end)

    it("handles response wrapped in markdown fences", function()
        local json = '```json\n[{"start_line": 1, "end_line": 1, "replacement": "x", "comment": "c"}]\n```'

        local mods, err = lag._parse_response(json)

        assert(err == nil, "Should not return an error")
        eq(1, #mods, "Should parse modification from fenced response")
    end)

    it("returns empty for whitespace-only response", function()
        local mods, err = lag._parse_response("   ")

        assert(err == nil, "Should not return an error for whitespace")
        eq(0, #mods, "Should return empty modifications for whitespace")
    end)
end)

describe("Lag Filter To Diff", function()
    it("keeps modifications within diff regions", function()
        local mods = {
            { start_line = 3, end_line = 4, replacement = "a", comment = "ok" },
            { start_line = 10, end_line = 11, replacement = "b", comment = "outside" },
        }

        local filtered = lag._filter_to_diff(mods, { { 2, 5 } })

        eq(1, #filtered, "Should keep only one modification")
        eq("ok", filtered[1].comment, "Should keep the one inside the region")
    end)

    it("returns empty when all modifications are outside", function()
        local mods = {
            { start_line = 10, end_line = 11, replacement = "a", comment = "out" },
        }

        local filtered = lag._filter_to_diff(mods, { { 2, 5 } })

        eq(0, #filtered, "Should filter out all modifications")
    end)

    it("keeps all when all are inside", function()
        local mods = {
            { start_line = 2, end_line = 3, replacement = "a", comment = "one" },
            { start_line = 4, end_line = 5, replacement = "b", comment = "two" },
        }

        local filtered = lag._filter_to_diff(mods, { { 1, 6 } })

        eq(2, #filtered, "Should keep all modifications")
    end)
end)

describe("Lag Lifecycle", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
        stream_opts_spy = nil
    end)

    it("start activates lag mode for the current buffer", function()
        local buf = make_buf({ "line1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        lag.start(noop_context, noop_session)

        assert(lag.is_active(buf), "Lag should be active after start")
    end)

    it("stop deactivates lag mode", function()
        local buf = make_buf({ "line1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)

        lag.stop()

        assert(not lag.is_active(buf), "Lag should not be active after stop")
    end)

    it("start is idempotent (warns on double start)", function()
        local buf = make_buf({ "line1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)

        lag.start(noop_context, noop_session)

        assert(lag.is_active(buf), "Lag should still be active")
    end)

    it("stop is safe when not active", function()
        local buf = make_buf({ "line1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        lag.stop()

        assert(not lag.is_active(buf), "Should not error on stop when inactive")
    end)

    it("reset clears all buffer state", function()
        local buf = make_buf({ "line1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)

        lag.reset()

        assert(not lag.is_active(buf), "Lag should not be active after reset")
    end)

    it("stores baseline on start", function()
        local buf = make_buf({ "hello", "world" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        lag.start(noop_context, noop_session)

        local state = lag.get_state(buf)
        eq({ "hello", "world" }, state.baseline, "Baseline should match initial buffer content")
    end)
end)

describe("Lag On-Save Processing", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
        stream_opts_spy = nil
    end)

    after_each(function()
        stub_api()
    end)

    it("skips processing when there is no diff", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)

        lag._on_save(buf, noop_context, noop_session)

        local state = lag.get_state(buf)
        eq(0, #state.modifications, "Should have no modifications when no diff")
    end)

    it("processes diff and applies modifications", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fixed bug"}]'

        lag._on_save(buf, noop_context, noop_session)

        local lines = get_buf_lines(buf)
        eq("FIXED", lines[2], "Line 2 should be replaced with the fix")
        local state = lag.get_state(buf)
        eq(1, #state.modifications, "Should have one modification")
        eq("fixed bug", state.modifications[1].comment, "Comment should match")
    end)

    it("rejects modifications outside the diff region", function()
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 4, "end_line": 4, "replacement": "NOPE", "comment": "outside diff"}]'

        lag._on_save(buf, noop_context, noop_session)

        local lines = get_buf_lines(buf)
        eq("d", lines[4], "Line 4 should be unchanged (outside diff)")
        local state = lag.get_state(buf)
        eq(0, #state.modifications, "Should have no modifications (all rejected)")
    end)

    it("handles LLM error gracefully", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED" })
        stub_error = "connection failed"

        lag._on_save(buf, noop_context, noop_session)

        local state = lag.get_state(buf)
        assert(not state.processing, "Processing flag should be cleared after error")
        eq(0, #state.modifications, "Should have no modifications after error")
    end)

    it("passes system prompt override via opts", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED" })

        lag._on_save(buf, noop_context, noop_session)

        assert(stream_opts_spy ~= nil, "Should pass opts to api.stream")
        assert(stream_opts_spy.system_prompt ~= nil, "Should include system_prompt in opts")
    end)

    it("updates baseline after applying modifications", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'

        lag._on_save(buf, noop_context, noop_session)

        local state = lag.get_state(buf)
        eq({ "a", "FIXED", "c" }, state.baseline, "Baseline should include AI modifications")
    end)

    it("does not treat AI modifications as a diff on next save", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        local call_count = 0
        api.stream = function(_messages, on_delta, on_done, _on_error, _opts)
            call_count = call_count + 1
            on_delta("[]")
            on_done()
            return function() end
        end

        lag._on_save(buf, noop_context, noop_session)

        eq(0, call_count, "Should not call LLM when no user changes exist")
    end)

    it("clears previous modifications before processing new ones", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIX1", "comment": "first"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED2" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIX2", "comment": "second"}]'

        lag._on_save(buf, noop_context, noop_session)

        local state = lag.get_state(buf)
        eq(1, #state.modifications, "Should only have the latest modification")
        eq("second", state.modifications[1].comment, "Should be the second modification")
    end)

    it("skips processing when diff is whitespace-only", function()
        local call_count = 0
        api.stream = function(_messages, on_delta, on_done, _on_error, _opts)
            call_count = call_count + 1
            on_delta("[]")
            on_done()
            return function() end
        end
        local buf = make_buf({ "a", "", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "   " })

        lag._on_save(buf, noop_context, noop_session)

        eq(0, call_count, "Should not call LLM for whitespace-only diff")
    end)

    it("skips processing when already processing", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED" })
        local state = lag.get_state(buf)
        state.processing = true

        lag._on_save(buf, noop_context, noop_session)

        eq(0, #state.modifications, "Should not process when already processing")
    end)

    it("includes context and session in the prompt", function()
        local context_called = false
        local session_called = false
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED" })
        local ctx_fn = function()
            context_called = true
            return "mock context"
        end
        local sess_fn = function()
            session_called = true
            return { conversation = { { role = "user", content = "prior msg" } } }
        end

        lag._on_save(buf, ctx_fn, sess_fn)

        assert(context_called, "Context function should have been called")
        assert(session_called, "Session function should have been called")
    end)
end)

describe("Lag Revert", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
    end)

    it("reverts the active modification to original code", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        lag._update_active(buf)
        local reverted = lag._revert_active(buf)

        assert(reverted, "Should return true on successful revert")
        local lines = get_buf_lines(buf)
        eq("CHANGED", lines[2], "Line 2 should be reverted to pre-AI state")
    end)

    it("removes the modification entry after revert", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        lag._update_active(buf)

        lag._revert_active(buf)

        local state = lag.get_state(buf)
        eq(0, #state.modifications, "Should have no modifications after revert")
    end)

    it("updates baseline after revert so revert is not a diff", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        lag._update_active(buf)

        lag._revert_active(buf)

        local state = lag.get_state(buf)
        eq({ "a", "CHANGED", "c" }, state.baseline, "Baseline should include the revert")
    end)

    it("returns false when no modifications exist", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)

        local reverted = lag._revert_active(buf)

        assert(not reverted, "Should return false when no modifications to revert")
    end)

    it("reverts nearest modification when cursor is between two", function()
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 5, false, { "A", "B", "C", "D", "E" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIX_A", "comment": "fix a"}, {"start_line": 5, "end_line": 5, "replacement": "FIX_E", "comment": "fix e"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        lag._update_active(buf)

        lag._revert_active(buf)

        local lines = get_buf_lines(buf)
        eq("FIX_A", lines[1], "First modification should remain")
        eq("E", lines[5], "Nearest modification (line 5) should be reverted")
    end)

    it("after revert the next closest becomes active", function()
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 5, false, { "A", "B", "C", "D", "E" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIX_A", "comment": "fix a"}, {"start_line": 5, "end_line": 5, "replacement": "FIX_E", "comment": "fix e"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        lag._update_active(buf)
        lag._revert_active(buf)

        local state = lag.get_state(buf)

        eq(1, #state.modifications, "Should have one modification left")
        eq(1, state.active_index, "Active should be the remaining modification")
    end)

    it("handles multiline replacement revert correctly", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "line1\\nline2\\nline3", "comment": "expanded"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        lag._update_active(buf)

        lag._revert_active(buf)

        local lines = get_buf_lines(buf)
        eq({ "a", "CHANGED", "c" }, lines, "Should revert multiline replacement to original single line")
    end)
end)

describe("Lag Active Tracking", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
    end)

    it("sets active to nearest modification on cursor move", function()
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 5, false, { "A", "B", "C", "D", "E" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIX_A", "comment": "fix a"}, {"start_line": 5, "end_line": 5, "replacement": "FIX_E", "comment": "fix e"}]'
        lag._on_save(buf, noop_context, noop_session)

        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        lag._update_active(buf)

        local state = lag.get_state(buf)
        eq(1, state.active_index, "Active should be the first modification (nearest to line 1)")
    end)

    it("switches active when cursor moves to another modification", function()
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 5, false, { "A", "B", "C", "D", "E" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIX_A", "comment": "fix a"}, {"start_line": 5, "end_line": 5, "replacement": "FIX_E", "comment": "fix e"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        lag._update_active(buf)

        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        lag._update_active(buf)

        local state = lag.get_state(buf)
        eq(2, state.active_index, "Active should switch to the second modification")
    end)

    it("does not re-render when active index unchanged", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        lag._update_active(buf)
        local state = lag.get_state(buf)
        local first_active = state.active_index

        lag._update_active(buf)

        eq(first_active, state.active_index, "Active index should not change on same cursor position")
    end)
end)

describe("Lag Clear Modifications", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
    end)

    it("clears all modifications without reverting code", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)

        lag._clear_modifications(buf)

        local state = lag.get_state(buf)
        eq(0, #state.modifications, "Should have no modifications after clear")
        local lines = get_buf_lines(buf)
        eq("FIXED", lines[2], "Code should remain modified (not reverted)")
    end)

    it("clears active index", function()
        local buf = make_buf({ "a", "b" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "CHANGED" })
        stub_response = '[{"start_line": 1, "end_line": 1, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)

        lag._clear_modifications(buf)

        local state = lag.get_state(buf)
        assert(state.active_index == nil, "Active index should be nil after clear")
    end)
end)

describe("Lag Diagnostics and Line Highlights", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}
    local ns_diagnostic = vim.api.nvim_create_namespace("ai_lag_diagnostic")

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "[]"
        stub_error = nil
    end)

    it("sets HINT diagnostics on modified lines", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "bug fix"}]'

        lag._on_save(buf, noop_context, noop_session)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq(1, #diags, "Should have one diagnostic")
        eq(vim.diagnostic.severity.HINT, diags[1].severity, "Diagnostic should be HINT severity")
        eq("lag", diags[1].source, "Diagnostic source should be 'lag'")
    end)

    it("diagnostic message contains only original code", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "bug fix"}]'

        lag._on_save(buf, noop_context, noop_session)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq("CHANGED", diags[1].message, "Diagnostic message should be the original code only")
    end)

    it("clears diagnostics when modifications are cleared", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)

        lag._clear_modifications(buf)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq(0, #diags, "Diagnostics should be cleared after clear_modifications")
    end)

    it("clears diagnostics when lag is stopped", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)

        lag.stop()

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq(0, #diags, "Diagnostics should be cleared after stop")
    end)

    it("clears diagnostics after revert", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'
        lag._on_save(buf, noop_context, noop_session)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        lag._update_active(buf)

        lag._revert_active(buf)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq(0, #diags, "Diagnostics should be cleared after reverting last modification")
    end)

    it("sets line highlights on modified lines via extmarks", function()
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })
        stub_response = '[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]'

        lag._on_save(buf, noop_context, noop_session)

        local state = lag.get_state(buf)
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, state.ns, 0, -1, { details = true })
        local has_line_hl = false
        for _, mark in ipairs(extmarks) do
            if mark[4] and mark[4].line_hl_group then
                has_line_hl = true
            end
        end
        assert(has_line_hl, "Should have extmarks with line_hl_group set")
    end)

    it("diagnostic shows multiline original code", function()
        local buf = make_buf({ "a", "b", "c", "d" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 3, false, { "X", "Y" })
        stub_response = '[{"start_line": 2, "end_line": 3, "replacement": "FIX1\\nFIX2", "comment": "multi fix"}]'

        lag._on_save(buf, noop_context, noop_session)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diagnostic })
        eq(1, #diags, "Should have one diagnostic for multiline modification")
        assert(diags[1].message:find("X", 1, true), "Diagnostic should contain first original line")
        assert(diags[1].message:find("Y", 1, true), "Diagnostic should contain second original line")
    end)
end)

describe("Lag Working Indicator Highlights", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}
    local ns_work = vim.api.nvim_create_namespace("ai_lag_working")

    before_each(function()
        lag.reset()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
    end)

    after_each(function()
        stub_api()
    end)

    it("shows working line highlights on diff region lines during processing", function()
        local captured_extmarks = nil
        api.stream = function(_messages, _on_delta, on_done, _on_error, _opts)
            local buf = vim.api.nvim_get_current_buf()
            captured_extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_work, 0, -1, { details = true })
            on_done()
            return function() end
        end
        local buf = make_buf({ "a", "b", "c", "d", "e" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 3, false, { "X", "Y" })

        lag._on_save(buf, noop_context, noop_session)

        assert(captured_extmarks ~= nil, "Should have captured extmarks during processing")
        local working_line_hls = 0
        for _, mark in ipairs(captured_extmarks) do
            if mark[4] and mark[4].line_hl_group == "AILagWorkingLine" then
                working_line_hls = working_line_hls + 1
            end
        end
        assert(working_line_hls >= 2, "Should highlight at least 2 lines in the diff region")
    end)

    it("clears working highlights when no modifications are made", function()
        api.stream = function(_messages, on_delta, on_done, _on_error, _opts)
            on_delta("[]")
            on_done()
            return function() end
        end
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })

        lag._on_save(buf, noop_context, noop_session)

        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_work, 0, -1, { details = true })
        eq(0, #extmarks, "Working highlights should be cleared when no modifications")
    end)

    it("clears working highlights when modifications are applied", function()
        api.stream = function(_messages, on_delta, on_done, _on_error, _opts)
            on_delta('[{"start_line": 2, "end_line": 2, "replacement": "FIXED", "comment": "fix"}]')
            on_done()
            return function() end
        end
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })

        lag._on_save(buf, noop_context, noop_session)

        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_work, 0, -1, { details = true })
        eq(0, #extmarks, "Working highlights should be cleared after modifications applied")
    end)

    it("clears working highlights on error", function()
        api.stream = function(_messages, _on_delta, _on_done, on_error, _opts)
            on_error("connection failed")
            return function() end
        end
        local buf = make_buf({ "a", "b", "c" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        lag.start(noop_context, noop_session)
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "CHANGED" })

        lag._on_save(buf, noop_context, noop_session)

        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_work, 0, -1, { details = true })
        eq(0, #extmarks, "Working highlights should be cleared after error")
    end)
end)
