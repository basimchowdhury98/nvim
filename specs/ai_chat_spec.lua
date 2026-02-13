local eq = assert.are.same

-- Set up test log directory for all tests
local debug = require("utils.ai.debug")
local test_log_dir = vim.fn.stdpath("log") .. "/ai/tests"
debug.set_log_dir(test_log_dir)
vim.fn.delete(test_log_dir, "rf")

local function get_chat_lines()
    local buf = require("utils.ai.chat").get_state().buf_id
    if buf and vim.api.nvim_buf_is_valid(buf) then
        return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
    return {}
end

local function chat_contains(text)
    for _, line in ipairs(get_chat_lines()) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function close_all_floats()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= "" then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
end

--- Create a scratch buffer with a name and filetype so it looks like a real file
local function create_named_buf(name, ft, lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].filetype = ft
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

local api = require("utils.ai.api")
local stub_response = "I am a test response"
local stub_error = nil
local stream_messages_spy = nil

local function stub_api()
    api.stream = function(messages, on_delta, on_done, on_error)
        stream_messages_spy = vim.deepcopy(messages)
        if stub_error then
            on_error(stub_error)
            return function() end
        end
        on_delta(stub_response)
        on_done()
        return function() end
    end
end

local function send_user_message(ai, message)
    local input_buf = ai.prompt()
    assert(input_buf ~= nil, "Input popup should have opened")

    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { message })
    vim.cmd("stopinsert")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
end

local function press(key)
    vim.cmd("stopinsert")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
end

describe("AI Chat Plugin", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    ai.setup()
    stub_api()
    vim.notify = function() end

    before_each(function()
        ai.clear()
        stub_response = "I am a test response"
        stub_error = nil
        stream_messages_spy = nil
    end)

    after_each(function()
        close_all_floats()
    end)

    it("toggle opens the chat panel", function()
        local win_count_before = #vim.api.nvim_list_wins()

        ai.toggle()

        eq(#vim.api.nvim_list_wins(), win_count_before + 1)
        assert(chat.is_open(), "Chat should be open")
    end)

    it("toggle closes the chat panel if already open", function()
        ai.toggle()

        ai.toggle()

        assert(not chat.is_open(), "Chat should be closed")
    end)

    it("chat panel returns focus to original window", function()
        local original_win = vim.api.nvim_get_current_win()

        ai.toggle()

        eq(vim.api.nvim_get_current_win(), original_win)
    end)

    it("prompt opens a floating input window", function()
        local input_buf = ai.prompt()

        assert(input_buf ~= nil, "Input popup should have opened")
        assert(vim.api.nvim_buf_is_valid(input_buf), "Input buffer should be valid")
    end)

    it("cancelling input with q does not send a message", function()
        ai.prompt()

        press("q")

        assert(not chat.is_open(), "Chat should not have opened")
    end)

    it("empty input does not send a message", function()
        ai.prompt()

        press("<CR>")

        assert(not chat.is_open(), "Chat should not have opened for empty input")
    end)

    it("sending a message opens chat and shows user message with assistant response", function()
        send_user_message(ai, "hello")

        assert(chat.is_open(), "Chat should open after sending")
        assert(chat_contains("**You:**"), "Should show user header")
        assert(chat_contains("hello"), "Should show user message")
        assert(chat_contains("**Assistant:**"), "Should show assistant header")
        assert(chat_contains("I am a test response"), "Should show assistant response")
    end)

    it("sending a message closes the input popup", function()
        local input_buf = ai.prompt()
        vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "hello" })
        vim.cmd("stopinsert")
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

        assert(not vim.api.nvim_buf_is_valid(input_buf), "Input buffer should be deleted after sending")
    end)

    it("streaming stops after response completes", function()
        send_user_message(ai, "hello")

        assert(not chat.is_streaming(), "Should not be streaming after response completes")
    end)

    it("multiple messages build up in the chat", function()
        send_user_message(ai, "first question")
        stub_response = "second answer"

        send_user_message(ai, "second question")

        assert(chat_contains("first question"), "First user message should be present")
        assert(chat_contains("I am a test response"), "First response should be present")
        assert(chat_contains("second question"), "Second user message should be present")
        assert(chat_contains("second answer"), "Second response should be present")
    end)

    it("shows error in chat when api returns an error", function()
        stub_error = "connection failed"

        send_user_message(ai, "hello")

        assert(chat_contains("**Error:**"), "Should show error header")
        assert(chat_contains("connection failed"), "Should show error message")
        assert(not chat.is_streaming(), "Should not be streaming after error")
    end)

    it("does not add failed message to conversation history", function()
        stub_error = "connection failed"
        send_user_message(ai, "this will fail")
        stub_error = nil
        stub_response = "success"

        send_user_message(ai, "this will work")

        for _, msg in ipairs(stream_messages_spy) do
            if msg.role == "user" then
                assert(not msg.content:find("this will fail"),
                    "Failed message should not be in conversation history")
            end
        end
    end)

    it("clear closes chat and resets conversation", function()
        send_user_message(ai, "hello")

        ai.clear()
        send_user_message(ai, "fresh start")

        assert(not chat_contains("hello"), "Old message should not be in chat after clear")
        for _, msg in ipairs(stream_messages_spy) do
            if msg.role == "user" then
                assert(not msg.content:find("hello"),
                    "Old message should not be in conversation after clear")
            end
        end
    end)
end)

describe("AI Chat Buffer Tracking", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        -- Ensure we're in a safe window before clearing (avoids E444)
        vim.cmd("enew")
        ai.clear()
        for _, buf in ipairs(test_bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        test_bufs = {}
        stub_response = "I am a test response"
        stub_error = nil
        stream_messages_spy = nil
    end)

    after_each(function()
        close_all_floats()
    end)

    it("includes the current buffer content in the first API message", function()
        local buf = create_named_buf("/tmp/test_track.lua", "lua", { "local x = 1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "explain this")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("test_track.lua", 1, true),
            "First API message should contain the tracked filename")
        assert(first_msg.content:find("local x = 1", 1, true),
            "First API message should contain the buffer content")
        assert(first_msg.content:find("explain this", 1, true),
            "First API message should contain the user text")
    end)

    it("tracks a new buffer visited after the first message", function()
        local buf_a = create_named_buf("/tmp/file_a.lua", "lua", { "aaa" })
        local buf_b = create_named_buf("/tmp/file_b.py", "python", { "bbb" })
        table.insert(test_bufs, buf_a)
        table.insert(test_bufs, buf_b)
        vim.api.nvim_set_current_buf(buf_a)
        send_user_message(ai, "first")
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf_b })

        send_user_message(ai, "second")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("file_a.lua", 1, true),
            "Context should contain first file")
        assert(first_msg.content:find("file_b.py", 1, true),
            "Context should contain second file after visiting it")
    end)

    it("sends updated buffer content on subsequent messages", function()
        local buf = create_named_buf("/tmp/evolving.lua", "lua", { "version 1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        send_user_message(ai, "first")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "version 2" })

        send_user_message(ai, "second")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("version 2", 1, true),
            "Context should contain the updated content")
        assert(not first_msg.content:find("version 1", 1, true),
            "Context should not contain the stale content")
    end)

    it("does not track buffers with no name or filetype", function()
        local scratch = vim.api.nvim_create_buf(false, true)
        table.insert(test_bufs, scratch)
        vim.api.nvim_set_current_buf(scratch)

        send_user_message(ai, "hello")

        local first_msg = stream_messages_spy[1]
        eq(first_msg.content, "hello", "Message should have no context prefix for unnamed buffers")
    end)

    it("does not duplicate a buffer visited multiple times", function()
        local buf = create_named_buf("/tmp/once.lua", "lua", { "content" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "first")

        vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })

        send_user_message(ai, "second")

        local first_msg = stream_messages_spy[1]
        local _, count = first_msg.content:gsub("once.lua", "")
        eq(count, 1, "Filename should appear exactly once in context")
    end)

    it("clear resets tracked buffers so next session starts fresh", function()
        local buf_a = create_named_buf("/tmp/old_file.lua", "lua", { "old" })
        table.insert(test_bufs, buf_a)
        vim.api.nvim_set_current_buf(buf_a)
        send_user_message(ai, "first session")
        ai.clear()

        local buf_b = create_named_buf("/tmp/new_file.lua", "lua", { "new" })
        table.insert(test_bufs, buf_b)
        vim.api.nvim_set_current_buf(buf_b)
        send_user_message(ai, "second session")

        local first_msg = stream_messages_spy[1]
        assert(not first_msg.content:find("old_file.lua", 1, true),
            "Old file should not appear after clear")
        assert(first_msg.content:find("new_file.lua", 1, true),
            "New file should appear in fresh session")
    end)

    it("only injects context into the first user message in the API payload", function()
        local buf = create_named_buf("/tmp/ctx_check.lua", "lua", { "ctx content" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "first")
        send_user_message(ai, "second")

        local second_user_msg = stream_messages_spy[3]
        eq(second_user_msg.role, "user", "Third message should be user")
        eq(second_user_msg.content, "second",
            "Non-first user messages should not have context injected")
    end)

    it("excludes buffers with sensitive patterns from tracking", function()
        local env_buf = create_named_buf("/tmp/.env", "sh", { "SECRET_KEY=abc123" })
        local appsettings_buf = create_named_buf("/tmp/appsettings.json", "json", { '{"password": "secret"}' })
        local normal_buf = create_named_buf("/tmp/app.lua", "lua", { "safe content" })
        table.insert(test_bufs, env_buf)
        table.insert(test_bufs, appsettings_buf)
        table.insert(test_bufs, normal_buf)
        vim.api.nvim_set_current_buf(env_buf)
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = env_buf })
        vim.api.nvim_set_current_buf(appsettings_buf)
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = appsettings_buf })
        vim.api.nvim_set_current_buf(normal_buf)

        send_user_message(ai, "check my code")

        local first_msg = stream_messages_spy[1]
        assert(not first_msg.content:find("SECRET_KEY", 1, true),
            "Env file content should not be in context")
        assert(not first_msg.content:find("password", 1, true),
            "Appsettings content should not be in context")
        assert(first_msg.content:find("safe content", 1, true),
            "Normal file content should be in context")
    end)
end)

describe("AI Inline Editing", function()
    local ai = require("utils.ai")
    local inline = require("utils.ai.inline")
    local inline_api = require("utils.ai.api")
    ai.setup()
    vim.notify = function() end

    local stub_inline_response = "function body() end"
    local stub_inline_error = nil
    local inline_spy = nil

    local function stub_inline_api()
        inline_api.inline_stream = function(selected_text, instruction, context, history, on_delta, on_done, on_error)
            inline_spy = {
                selected_text = selected_text,
                instruction = instruction,
                context = context,
                history = history,
            }
            if stub_inline_error then
                on_error(stub_inline_error)
                return function() end
            end
            on_delta(stub_inline_response)
            on_done()
            return function() end
        end
    end

    stub_inline_api()

    before_each(function()
        ai.clear()
        stub_inline_response = "function body() end"
        stub_inline_error = nil
        inline_spy = nil
    end)

    after_each(function()
        close_all_floats()
    end)

    it("executes inline edit and replaces selection with streamed response", function()
        local buf = create_named_buf("/tmp/inline_test.lua", "lua", { "local x = 1", "local y = 2", "local z = 3" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 1,
            start_col = 0,
            end_row = 1,
            end_col = 11,
            text = "local y = 2",
        }

        inline.execute(selection, "replace with z", nil, nil)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        eq(lines[1], "local x = 1", "First line should be unchanged")
        eq(lines[2], "function body() end", "Second line should be replaced with response")
        eq(lines[3], "local z = 3", "Third line should be unchanged")

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("passes selected text and instruction to api.inline_stream", function()
        local buf = create_named_buf("/tmp/inline_spy.lua", "lua", { "original code" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 13,
            text = "original code",
        }

        inline.execute(selection, "make it better", nil, nil)

        assert(inline_spy ~= nil, "inline_stream should have been called")
        eq(inline_spy.selected_text, "original code", "Should pass selected text")
        eq(inline_spy.instruction, "make it better", "Should pass instruction")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("passes context when provided", function()
        local buf = create_named_buf("/tmp/inline_ctx.lua", "lua", { "code" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 4,
            text = "code",
        }

        inline.execute(selection, "edit", "some context", nil)

        eq(inline_spy.context, "some context", "Should pass context to API")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("passes conversation history when provided", function()
        local buf = create_named_buf("/tmp/inline_hist.lua", "lua", { "code" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 4,
            text = "code",
        }
        local history = {
            { role = "user", content = "previous question" },
            { role = "assistant", content = "previous answer" },
        }

        inline.execute(selection, "edit", nil, history)

        assert(inline_spy.history ~= nil, "Should pass history to API")
        eq(#inline_spy.history, 2, "History should have 2 messages")
        eq(inline_spy.history[1].content, "previous question", "First history message should match")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles sentinel response without modifying buffer", function()
        stub_inline_response = "__NO_INLINE_CODE_PROMPT__"
        local buf = create_named_buf("/tmp/inline_sentinel.lua", "lua", { "unchanged" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 9,
            text = "unchanged",
        }

        inline.execute(selection, "what is this?", nil, nil)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        eq(lines[1], "unchanged", "Buffer should not be modified when sentinel is returned")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles multiline replacement", function()
        stub_inline_response = "line1\nline2\nline3"
        local buf = create_named_buf("/tmp/inline_multi.lua", "lua", { "single line" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 11,
            text = "single line",
        }

        inline.execute(selection, "expand", nil, nil)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        eq(lines[1], "line1", "First replacement line")
        eq(lines[2], "line2", "Second replacement line")
        eq(lines[3], "line3", "Third replacement line")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles partial line selection replacement", function()
        stub_inline_response = "REPLACED"
        local buf = create_named_buf("/tmp/inline_partial.lua", "lua", { "prefix MIDDLE suffix" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 7,
            end_row = 0,
            end_col = 13,
            text = "MIDDLE",
        }

        inline.execute(selection, "replace middle", nil, nil)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        eq(lines[1], "prefix REPLACED suffix", "Should replace only the selected portion")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles error from api gracefully", function()
        stub_inline_error = "API failed"
        local notified = nil
        vim.notify = function(msg) notified = msg end
        local buf = create_named_buf("/tmp/inline_error.lua", "lua", { "code" })
        vim.api.nvim_set_current_buf(buf)

        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 4,
            text = "code",
        }

        inline.execute(selection, "edit", nil, nil)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        eq(lines[1], "code", "Buffer should be unchanged on error")
        assert(notified and notified:find("API failed"), "Should notify user of error")
        vim.api.nvim_buf_delete(buf, { force = true })
        vim.notify = function() end
    end)

    it("cleans up spinner after completion", function()
        local buf = create_named_buf("/tmp/inline_spinner.lua", "lua", { "line1", "line2", "line3" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 1,
            start_col = 0,
            end_row = 1,
            end_col = 5,
            text = "line2",
        }

        inline.execute(selection, "replace", nil, nil)

        local ns_id = vim.api.nvim_create_namespace("ai_inline_spinner")
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
        eq(#extmarks, 0, "All spinner extmarks should be cleaned up after completion")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("cleans up spinner on error", function()
        stub_inline_error = "API failed"
        vim.notify = function() end
        local buf = create_named_buf("/tmp/inline_spinner_err.lua", "lua", { "code" })
        vim.api.nvim_set_current_buf(buf)
        local selection = {
            buf = buf,
            start_row = 0,
            start_col = 0,
            end_row = 0,
            end_col = 4,
            text = "code",
        }

        inline.execute(selection, "edit", nil, nil)

        local ns_id = vim.api.nvim_create_namespace("ai_inline_spinner")
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
        eq(#extmarks, 0, "All spinner extmarks should be cleaned up after error")
        vim.api.nvim_buf_delete(buf, { force = true })
        stub_inline_error = nil
    end)
end)

describe("AI Debug", function()
    it("get_log_dir returns custom path when set", function()
        local log_dir = debug.get_log_dir()

        assert(log_dir == test_log_dir, "Expected " .. test_log_dir .. ", got " .. log_dir)
    end)

    it("log writes to file", function()
        local date = os.date("%Y-%m-%d")
        local log_path = test_log_dir .. "/" .. date .. ".log"

        debug.log("test message from spec")

        local f = io.open(log_path, "r")
        assert(f, "Log file should exist after logging")
        local content = f:read("*a")
        f:close()

        assert(content:find("test message from spec"), "Log file should contain the message")
    end)
end)
