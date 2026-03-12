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
--- If name is relative, it's prefixed with cwd to make it a project file
local function create_named_buf(name, ft, lines)
    local buf = vim.api.nvim_create_buf(true, false)
    local full_name = name
    if not name:match("^/") then
        full_name = vim.fn.getcwd() .. "/" .. name
    end
    vim.api.nvim_buf_set_name(buf, full_name)
    vim.bo[buf].filetype = ft
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

local api = require("utils.ai.api")
local stub_response = "I am a test response"
local stub_error = nil
local stub_hang = false
local stub_cancel_spy = nil
local stream_messages_spy = nil

local function stub_api()
    api.stream = function(messages, on_delta, on_done, on_error)
        stream_messages_spy = vim.deepcopy(messages)
        if stub_error then
            on_error(stub_error)
            return function() end
        end
        if stub_hang then
            stub_cancel_spy = false
            return function() stub_cancel_spy = true end
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
        ai.reset_all()
        ai.activate()
        stub_api()
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

        eq(#vim.api.nvim_list_wins(), win_count_before + 1, "One new window should be open")
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

        eq(vim.api.nvim_get_current_win(), original_win, "Focus should return to original window")
    end)

    it("prompt opens a floating input window", function()
        local input_buf = ai.prompt()

        assert(input_buf ~= nil, "Input popup should have opened")
        assert(vim.api.nvim_buf_is_valid(input_buf), "Input buffer should be valid")
    end)

    it("cancelling input with q does not send a message", function()
        ai.prompt()

        press("q")

        assert(chat.is_open(), "Chat should have opened to show previous context")
        assert(stream_messages_spy == nil, "No message should have been sent to the provider")
    end)

    it("empty input does not send a message", function()
        ai.prompt()

        press("<CR>")

        assert(chat.is_open(), "Chat should have opened to show previous context")
        assert(stream_messages_spy == nil, "No message should have been sent to the provider")
    end)

    it("sending a message opens chat and shows user message with assistant response", function()
        send_user_message(ai, "hello")

        assert(chat.is_open(), "Chat should open after sending")
        assert(chat_contains("You:"), "Should show user header")
        assert(chat_contains("hello"), "Should show user message")
        assert(chat_contains("Assistant:"), "Should show assistant header")
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

    it("second message replaces the first in the chat panel", function()
        send_user_message(ai, "first question")
        stub_response = "second answer"

        send_user_message(ai, "second question")

        assert(not chat_contains("first question"), "First user message should be gone")
        assert(not chat_contains("I am a test response"), "First response should be gone")
        assert(chat_contains("second question"), "Second user message should be present")
        assert(chat_contains("second answer"), "Second response should be present")
    end)

    it("shows error in chat when api returns an error", function()
        stub_error = "connection failed"

        send_user_message(ai, "hello")

        assert(chat_contains("Error:"), "Should show error header")
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

    it("stop closes chat and resets conversation", function()
        send_user_message(ai, "hello")
        ai.stop()
        ai.activate()

        send_user_message(ai, "fresh start")

        assert(not chat_contains("hello"), "Old message should not be in chat after stop")
        for _, msg in ipairs(stream_messages_spy) do
            if msg.role == "user" then
                assert(not msg.content:find("hello"),
                    "Old message should not be in conversation after stop")
            end
        end
    end)
end)

describe("AI Chat Cancel", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    ai.setup()
    stub_api()
    vim.notify = function() end

    before_each(function()
        ai.reset_all()
        ai.activate()
        stub_api()
        stub_response = "I am a test response"
        stub_error = nil
        stub_hang = false
        stub_cancel_spy = nil
        stream_messages_spy = nil
    end)

    after_each(function()
        stub_hang = false
        close_all_floats()
    end)

    it("cancel interrupts an in-flight request", function()
        stub_hang = true
        send_user_message(ai, "hanging request")

        ai.cancel()

        assert(stub_cancel_spy == true, "Cancel function should have been called")
        assert(chat_contains("[interrupted]"), "Chat should show interrupted marker")
        assert(not chat.is_streaming(), "Should not be streaming after cancel")
    end)

    it("cancel removes the pending user message from history", function()
        stub_hang = true
        send_user_message(ai, "this will be cancelled")
        ai.cancel()
        stub_hang = false
        stub_response = "fresh response"

        send_user_message(ai, "followup")

        for _, msg in ipairs(stream_messages_spy) do
            if msg.role == "user" then
                assert(not msg.content:find("this will be cancelled"),
                    "Cancelled message should not be in conversation history")
            end
        end
        assert(chat_contains("fresh response"), "Followup should get a response")
    end)

    it("cancel is a no-op when nothing is streaming", function()
        ai.cancel()

        assert(not chat.is_open(), "Chat should not have opened")
    end)

    it("can send a new message after cancelling", function()
        stub_hang = true
        send_user_message(ai, "will cancel")
        ai.cancel()
        stub_hang = false

        send_user_message(ai, "new message")

        assert(chat_contains("new message"), "New user message should appear")
        assert(chat_contains("I am a test response"), "New response should appear")
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
        ai.reset_all()
        ai.activate()
        stub_api()
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

    it("includes editor context metadata in user API messages", function()
        local buf = create_named_buf("test_track.lua", "lua", { "local x = 1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "explain this")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("EDITOR CONTEXT:", 1, true),
            "First API message should contain editor context header")
        assert(first_msg.content:find("test_track.lua", 1, true),
            "First API message should contain the filename")
        assert(not first_msg.content:find("local x = 1", 1, true),
            "First API message should NOT contain file contents")
        assert(first_msg.content:find("explain this", 1, true),
            "First API message should contain the user text")
    end)

    it("includes all open project buffers in context", function()
        local buf_a = create_named_buf("file_a.lua", "lua", { "aaa" })
        local buf_b = create_named_buf("file_b.py", "python", { "bbb" })
        table.insert(test_bufs, buf_a)
        table.insert(test_bufs, buf_b)
        vim.api.nvim_set_current_buf(buf_a)

        send_user_message(ai, "check both")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("file_a.lua", 1, true),
            "Context should contain first file")
        assert(first_msg.content:find("file_b.py", 1, true),
            "Context should contain second file")
    end)

    it("injects editor context into every user message", function()
        local buf = create_named_buf("evolving.lua", "lua", { "version 1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)
        send_user_message(ai, "first")

        send_user_message(ai, "second")

        local first_msg = stream_messages_spy[1]
        local third_msg = stream_messages_spy[3]
        assert(first_msg.content:find("EDITOR CONTEXT:", 1, true),
            "First user message should have editor context")
        assert(third_msg.content:find("EDITOR CONTEXT:", 1, true),
            "Second user message should also have editor context")
    end)

    it("does not track buffers with no name or filetype", function()
        local scratch = vim.api.nvim_create_buf(false, true)
        table.insert(test_bufs, scratch)
        vim.api.nvim_set_current_buf(scratch)

        send_user_message(ai, "hello")

        local first_msg = stream_messages_spy[1]
        eq(first_msg.content, "hello", "Message should have no context prefix for unnamed buffers")
    end)

    it("lists buffer once in open buffers line", function()
        local buf = create_named_buf("once.lua", "lua", { "content" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "check")

        local first_msg = stream_messages_spy[1]
        local open_line = first_msg.content:match("Open buffers: ([^\n]+)")
        assert(open_line, "Should have an Open buffers line")
        local _, count = open_line:gsub("once.lua", "")
        eq(count, 1, "Filename should appear exactly once in open buffers")
    end)

    it("injects context into all user messages in the API payload", function()
        local buf = create_named_buf("ctx_check.lua", "lua", { "ctx content" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        send_user_message(ai, "first")
        send_user_message(ai, "second")

        local second_user_msg = stream_messages_spy[3]
        eq(second_user_msg.role, "user", "Third message should be user")
        assert(second_user_msg.content:find("EDITOR CONTEXT:", 1, true),
            "Second user message should have editor context")
        assert(second_user_msg.content:find("second", 1, true),
            "Second user message should contain the user text")
    end)

    it("excludes buffers with sensitive patterns from context", function()
        local env_buf = create_named_buf(".env", "sh", { "SECRET_KEY=abc123" })
        local appsettings_buf = create_named_buf("appsettings.json", "json", { '{"password": "secret"}' })
        local normal_buf = create_named_buf("app.lua", "lua", { "safe content" })
        table.insert(test_bufs, env_buf)
        table.insert(test_bufs, appsettings_buf)
        table.insert(test_bufs, normal_buf)
        vim.api.nvim_set_current_buf(normal_buf)

        send_user_message(ai, "check my code")

        local first_msg = stream_messages_spy[1]
        assert(not first_msg.content:find(".env", 1, true),
            "Env file should not appear in context")
        assert(not first_msg.content:find("appsettings", 1, true),
            "Appsettings file should not appear in context")
        assert(first_msg.content:find("app.lua", 1, true),
            "Normal file should appear in context")
    end)
end)

describe("AI Chat Quoted Selection", function()
    local ai = require("utils.ai")
    require("utils.ai.chat")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_api()
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

    it("includes quoted selection with filename and line range in API message", function()
        local selection = {
            filename = "/project/app.lua",
            start_line = 10,
            end_line = 12,
            lang = "lua",
            text = "local x = 1",
        }

        ai.send("explain this", selection)

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("[Referring to /project/app.lua:10-12]", 1, true),
            "API message should contain the referring header")
        assert(first_msg.content:find("local x = 1", 1, true),
            "API message should contain the selected text")
        assert(first_msg.content:find("explain this", 1, true),
            "API message should contain the user question")
    end)

    it("includes language in the code fence", function()
        local selection = {
            filename = "/project/app.py",
            start_line = 5,
            end_line = 5,
            lang = "python",
            text = "x = 1",
        }

        ai.send("what does this do", selection)

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("```python", 1, true),
            "API message should contain language-tagged code fence")
    end)

    it("sends message without quoted context when no selection is provided", function()
        ai.send("hello")

        local first_msg = stream_messages_spy[1]
        assert(not first_msg.content:find("[Referring to", 1, true),
            "API message should not contain referring header without selection")
        assert(first_msg.content:find("hello", 1, true),
            "API message should contain the user text")
    end)

    it("stores quoted context in conversation history for multi-turn continuity", function()
        local selection = {
            filename = "/project/app.lua",
            start_line = 1,
            end_line = 1,
            lang = "lua",
            text = "local x = 1",
        }

        ai.send("explain this", selection)
        ai.send("can you elaborate")

        -- Second API call should have the quoted context in the first history message
        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("[Referring to", 1, true),
            "First message in history should still have the quoted context")
    end)

    it("shows quoted metadata and user question in chat panel", function()
        local selection = {
            filename = "/project/app.lua",
            start_line = 1,
            end_line = 3,
            lang = "lua",
            text = "local x = 1",
        }

        ai.send("explain this", selection)

        assert(chat_contains("explain this"), "Chat should show the user question")
        assert(chat_contains("> /project/app.lua:1-3"), "Chat should show the quoted metadata")
        assert(not chat_contains("local x = 1"), "Chat should not show the full quoted code")
    end)

    it("handles selection with empty lang gracefully", function()
        local selection = {
            filename = "/project/data.txt",
            start_line = 3,
            end_line = 3,
            lang = "",
            text = "some data",
        }

        ai.send("what is this", selection)

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("```\nsome data", 1, true),
            "Code fence should have no language when lang is empty")
    end)
end)

describe("AI Debug", function()
    it("get_log_dir returns custom path when set", function()
        local log_dir = debug.get_log_dir()

        assert(log_dir == test_log_dir, "Expected " .. test_log_dir .. ", got " .. log_dir)
    end)

    it("log writes to file", function()
        local log_path = test_log_dir .. "/" .. os.date("%Y-%m-%d") .. ".log"

        debug.log("test message from spec")

        local f = io.open(log_path, "r")
        assert(f, "Log file should exist after logging")
        local content = f:read("*a")
        f:close()
        assert(content:find("test message from spec"), "Log file should contain the message")
    end)
end)

describe("AI Project-Scoped Sessions", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local original_cwd
    local test_bufs = {}

    before_each(function()
        original_cwd = vim.fn.getcwd()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_api()
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
        vim.fn.chdir(original_cwd)
    end)

    it("switching cwd starts a fresh conversation", function()
        vim.fn.chdir("/tmp")
        send_user_message(ai, "project A message")

        vim.fn.chdir("/")
        stub_response = "project B response"
        send_user_message(ai, "project B message")

        assert(not chat_contains("project A message"), "Project A message should not appear in project B chat")
        assert(chat_contains("project B message"), "Project B message should appear")
        assert(chat_contains("project B response"), "Project B response should appear")
    end)

    it("returning to previous cwd shows empty panel (single Q&A view)", function()
        vim.fn.chdir("/tmp")
        send_user_message(ai, "project A first")
        vim.fn.chdir("/")
        send_user_message(ai, "project B message")

        vim.fn.chdir("/tmp")
        ai.toggle()

        assert(not chat_contains("project A first"), "Panel should be empty after project switch")
        assert(not chat_contains("project B message"), "Project B message should not appear")
    end)

    it("conversation history is scoped to project", function()
        vim.fn.chdir("/tmp")
        send_user_message(ai, "tmp question")

        vim.fn.chdir("/var")
        send_user_message(ai, "var question")

        local first_msg = stream_messages_spy[1]
        assert(not first_msg.content:find("tmp question", 1, true),
            "Project B should not have project A's history in API messages")
        assert(first_msg.content:find("var question", 1, true),
            "Project B should have its own user message")
    end)

    it("stop only affects the current project's history", function()
        vim.fn.chdir("/tmp")
        send_user_message(ai, "tmp message")
        vim.fn.chdir("/")
        send_user_message(ai, "root message")
        ai.stop()
        ai.activate()

        vim.fn.chdir("/tmp")
        stub_response = "tmp response 2"
        send_user_message(ai, "tmp followup")

        assert(#stream_messages_spy >= 3,
            "API should receive previous history from /tmp project")
        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("tmp message", 1, true),
            "Project A history should survive project B stop")
    end)

    it("re-renders chat when toggling after cwd change", function()
        vim.fn.chdir("/tmp")
        send_user_message(ai, "tmp content")
        chat.close()

        vim.fn.chdir("/")
        ai.toggle()

        assert(not chat_contains("tmp content"), "Should not show project A content after cwd change")
    end)
end)

describe("AI Provider Resolution", function()
    local ai = require("utils.ai")
    ai.setup()
    stub_api()
    vim.notify = function() end

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_api()
        stub_response = "I am a test response"
        stub_error = nil
        stream_messages_spy = nil
    end)

    after_each(function()
        close_all_floats()
    end)

    it("get_provider returns 'opencode' by default when AI_WORK is not set", function()
        local original = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)

        local provider = api.get_provider()

        eq(provider, "opencode", "Default provider should be opencode")
        vim.fn.setenv("AI_WORK", original)
    end)

    it("get_provider returns 'anthropic' when AI_WORK is set", function()
        local original = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", "true")

        local provider = api.get_provider()

        eq(provider, "anthropic", "Provider should be anthropic in work mode")
        vim.fn.setenv("AI_WORK", original)
    end)
end)

describe("AI Activation Lifecycle", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    local lag_mod = require("utils.ai.lag")
    ai.setup()
    stub_api()
    vim.notify = function() end

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        stub_api()
        stub_response = "I am a test response"
        stub_error = nil
        stub_hang = false
        stream_messages_spy = nil
    end)

    after_each(function()
        stub_hang = false
        close_all_floats()
        lag_mod.stop()
    end)

    it("system starts inactive", function()
        local is_active = ai.is_active()

        eq(is_active, false, "AI should start inactive")
    end)

    it("toggle is a no-op when inactive", function()
        ai.toggle()

        assert(not chat.is_open(), "Chat should not open when inactive")
    end)

    it("continue_response is a no-op when inactive", function()
        ai.continue_response()

        assert(not chat.is_open(), "Chat should not open from continue when inactive")
    end)

    it("cancel is a no-op when inactive", function()
        ai.cancel()

        assert(not chat.is_open(), "Chat should not open from cancel when inactive")
    end)

    it("prompt opens input with onboarding title when inactive", function()
        local input_buf = ai.prompt()

        assert(input_buf ~= nil, "Input popup should open even when inactive")
        assert(vim.api.nvim_buf_is_valid(input_buf), "Input buffer should be valid")
    end)

    it("cancelling onboarding prompt keeps system inactive", function()
        ai.prompt()

        press("q")

        eq(ai.is_active(), false, "AI should remain inactive after cancelling onboarding")
        assert(not chat.is_open(), "Chat should not have opened")
    end)

    it("empty onboarding prompt keeps system inactive", function()
        ai.prompt()

        press("<CR>")

        eq(ai.is_active(), false, "AI should remain inactive after empty onboarding input")
        assert(not chat.is_open(), "Chat should not have opened")
    end)

    it("answering onboarding prompt activates the system", function()
        send_user_message(ai, "building a REST API")

        eq(ai.is_active(), true, "AI should be active after answering onboarding")
        assert(chat.is_open(), "Chat should be open after activation")
    end)

    it("onboarding message is prefixed with session context", function()
        send_user_message(ai, "building a REST API")

        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("What we are working on this session: building a REST API", 1, true),
            "First message should be prefixed with session context")
    end)

    it("onboarding does not start lag mode", function()
        send_user_message(ai, "building a REST API")

        assert(not lag_mod.is_running(), "Lag mode should not auto-start after onboarding")
    end)

    it("toggle works after activation", function()
        send_user_message(ai, "starting work")
        chat.close()

        ai.toggle()

        assert(chat.is_open(), "Toggle should open chat after activation")
    end)

    it("subsequent prompts use normal title after activation", function()
        send_user_message(ai, "starting work")

        local input_buf = ai.prompt()

        assert(input_buf ~= nil, "Input popup should open for subsequent messages")
        assert(vim.api.nvim_buf_is_valid(input_buf), "Input buffer should be valid")
    end)

    it("AIStop deactivates the system", function()
        send_user_message(ai, "starting work")

        ai.stop()

        eq(ai.is_active(), false, "AI should be inactive after stop")
        assert(not chat.is_open(), "Chat should be closed after stop")
        assert(not lag_mod.is_running(), "Lag mode should be stopped after stop")
    end)

    it("prompt shows onboarding again after AIStop", function()
        send_user_message(ai, "first session")
        ai.stop()

        send_user_message(ai, "new session")

        eq(ai.is_active(), true, "AI should be active again after new onboarding")
        local first_msg = stream_messages_spy[1]
        assert(first_msg.content:find("What we are working on this session: new session", 1, true),
            "New session should have prefixed onboarding message")
        assert(not first_msg.content:find("first session", 1, true),
            "Old session message should not appear in new session")
    end)

    it("reset_all deactivates the system", function()
        send_user_message(ai, "starting work")

        ai.reset_all()

        eq(ai.is_active(), false, "AI should be inactive after reset_all")
    end)
end)

describe("AI Context Dump", function()
    local ai = require("utils.ai")
    local lag_mod = require("utils.ai.lag")
    ai.setup()
    stub_api()
    vim.notify = function() end

    local test_bufs = {}

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_api()
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
        lag_mod.stop()
    end)

    it("snapshot includes project and active state", function()
        local snapshot = ai.build_state_snapshot()

        eq(snapshot.project, vim.fn.getcwd(), "Project should be cwd")
        eq(snapshot.active, true, "Active should reflect current state")
    end)

    it("snapshot includes conversation history", function()
        send_user_message(ai, "hello world")

        local snapshot = ai.build_state_snapshot()

        eq(#snapshot.conversation, 2, "Should have user + assistant messages")
        assert(snapshot.conversation[1].content:find("hello world", 1, true),
            "First message should contain user text")
    end)

    it("snapshot includes project buffers", function()
        local buf = create_named_buf("dump_test.lua", "lua", { "local x = 1" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        local snapshot = ai.build_state_snapshot()

        assert(#snapshot.project_buffers >= 1, "Should have at least one project buffer")
        local found = false
        for _, name in ipairs(snapshot.project_buffers) do
            if name:find("dump_test.lua", 1, true) then
                found = true
            end
        end
        assert(found, "Project buffers should include the test buffer")
    end)

    it("snapshot includes editor context metadata", function()
        local buf = create_named_buf("ctx_dump.lua", "lua", { "local y = 2" })
        table.insert(test_bufs, buf)
        vim.api.nvim_set_current_buf(buf)

        local snapshot = ai.build_state_snapshot()

        assert(snapshot.editor_context ~= nil, "Editor context should be present")
        assert(snapshot.editor_context:find("ctx_dump.lua", 1, true),
            "Editor context should mention the test file")
        assert(snapshot.editor_context:find("EDITOR CONTEXT:", 1, true),
            "Editor context should have the EDITOR CONTEXT header")
        assert(not snapshot.editor_context:find("local y = 2", 1, true),
            "Editor context should NOT contain file contents")
    end)

    it("snapshot includes lag state", function()
        local snapshot = ai.build_state_snapshot()

        assert(snapshot.lag ~= nil, "Lag state should be present")
        eq(type(snapshot.lag.running), "boolean", "Lag running should be a boolean")
        eq(type(snapshot.lag.buffers), "table", "Lag buffers should be a table")
    end)

    it("snapshot includes usage totals", function()
        local snapshot = ai.build_state_snapshot()

        assert(snapshot.usage ~= nil, "Usage should be present")
        eq(type(snapshot.usage.input), "number", "Usage input should be a number")
        eq(type(snapshot.usage.output), "number", "Usage output should be a number")
        eq(type(snapshot.usage.requests), "number", "Usage requests should be a number")
    end)

    it("context_dump writes a file to the log directory", function()
        send_user_message(ai, "dump test message")

        ai.context_dump()

        local log_dir = debug.get_log_dir()
        local files = vim.fn.glob(log_dir .. "/context_dump_*.txt", false, true)
        assert(#files >= 1, "Should have written at least one dump file")
        local content = table.concat(vim.fn.readfile(files[#files]), "\n")
        assert(content:find("AI CONTEXT DUMP", 1, true), "Dump should have header")
        assert(content:find("dump test message", 1, true), "Dump should contain conversation")
        assert(content:find("EDITOR CONTEXT", 1, true), "Dump should have editor context section")
        assert(content:find("LAG MODE", 1, true), "Dump should have lag section")
    end)
end)

describe("AI Chat Thinking", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    ai.setup()
    vim.notify = function() end

    local stub_thinking = nil

    local function stub_api_with_thinking()
        api.stream = function(messages, on_delta, on_done, on_error, opts)
            stream_messages_spy = vim.deepcopy(messages)
            if stub_error then
                on_error(stub_error)
                return function() end
            end
            if stub_thinking and opts and opts.on_thinking then
                opts.on_thinking(stub_thinking)
            end
            on_delta(stub_response)
            on_done()
            return function() end
        end
    end

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_response = "The answer is 42"
        stub_thinking = nil
        stub_error = nil
        stream_messages_spy = nil
        stub_api_with_thinking()
    end)

    after_each(function()
        close_all_floats()
    end)

    it("stores thinking content in conversation history", function()
        stub_thinking = "Let me reason about this"
        send_user_message(ai, "what is the answer?")

        local session = ai.get_session()
        local assistant_msg = session.conversation[#session.conversation]

        eq(assistant_msg.role, "assistant", "Last message should be assistant")
        eq(assistant_msg.thinking, "Let me reason about this", "Should store thinking content")
        eq(assistant_msg.content, "The answer is 42", "Should store content separately")
    end)

    it("omits thinking field when no thinking content", function()
        stub_thinking = nil
        send_user_message(ai, "quick question")

        local session = ai.get_session()
        local assistant_msg = session.conversation[#session.conversation]

        eq(assistant_msg.role, "assistant", "Last message should be assistant")
        eq(assistant_msg.thinking, nil, "Should not have thinking field when empty")
    end)

    it("shows collapsed thinking indicator in chat", function()
        stub_thinking = "Step 1: analyze\nStep 2: conclude"
        send_user_message(ai, "think about this")

        assert(chat_contains("Thinking... (2 lines)"), "Should show collapsed thinking indicator with line count")
    end)

    it("shows 1 line label for single line thinking", function()
        stub_thinking = "Just one thought"
        send_user_message(ai, "think briefly")

        assert(chat_contains("Thinking... (1 line)"), "Should show singular line label")
    end)

    it("toggle_thinking expands collapsed thinking block", function()
        stub_thinking = "My reasoning here"
        send_user_message(ai, "think about this")

        ai.toggle_thinking()

        assert(chat_contains("My reasoning here"), "Should show thinking content after expand")
    end)

    it("toggle_thinking collapses expanded thinking block", function()
        stub_thinking = "My reasoning here"
        send_user_message(ai, "think about this")

        ai.toggle_thinking()
        ai.toggle_thinking()

        assert(chat_contains("Thinking... (1 line)"), "Should show collapsed indicator after collapse")
        local found_content = false
        for _, line in ipairs(get_chat_lines()) do
            if line:find("My reasoning here", 1, true) then
                found_content = true
            end
        end
        assert(not found_content, "Thinking content should be hidden after collapse")
    end)

    it("toggle_thinking is a no-op when inactive", function()
        ai.reset_all()

        ai.toggle_thinking()

        assert(not chat.is_open(), "Chat should not open when inactive")
    end)

    it("toggle_thinking is a no-op when no thinking blocks exist", function()
        stub_thinking = nil
        send_user_message(ai, "no thinking here")

        ai.toggle_thinking()

        local chat_state = chat.get_state()
        eq(chat_state.thinking_expanded, false, "Should remain collapsed when no blocks")
    end)

    it("clear resets thinking state", function()
        stub_thinking = "Some thoughts"
        send_user_message(ai, "think first")

        ai.toggle_thinking()
        chat.clear()

        local chat_state = chat.get_state()
        eq(#chat_state.thinking_blocks, 0, "Thinking blocks should be empty after clear")
        eq(chat_state.thinking_expanded, false, "Thinking expanded should be false after clear")
    end)
end)

describe("AI Chat Tool Use Rendering", function()
    local ai = require("utils.ai")
    ai.setup()
    vim.notify = function() end

    local stub_tool_uses = nil

    local function stub_api_with_tools()
        api.stream = function(messages, on_delta, on_done, on_error, opts)
            stream_messages_spy = vim.deepcopy(messages)
            if stub_error then
                on_error(stub_error)
                return function() end
            end
            if stub_tool_uses and opts and opts.on_tool_use then
                for _, tool_info in ipairs(stub_tool_uses) do
                    opts.on_tool_use(tool_info)
                end
            end
            on_delta(stub_response)
            on_done()
            return function() end
        end
    end

    before_each(function()
        vim.cmd("enew")
        ai.reset_all()
        ai.activate()
        stub_response = "The file contains useful code"
        stub_tool_uses = nil
        stub_error = nil
        stream_messages_spy = nil
        stub_api_with_tools()
    end)

    after_each(function()
        close_all_floats()
    end)

    it("renders tool use line in chat buffer", function()
        stub_tool_uses = {
            { tool = "read", status = "completed", input = { filePath = "/workspace/foo.lua" }, output = "local x = 1" },
        }

        send_user_message(ai, "read the file")
        local lines = get_chat_lines()

        local found = false
        for _, line in ipairs(lines) do
            if line:find("read", 1, true) and line:find("/workspace/foo.lua", 1, true) then
                found = true
                break
            end
        end
        assert(found, "Chat should contain tool use line with tool name and path")
    end)

    it("renders tool use with pattern input", function()
        stub_tool_uses = {
            { tool = "grep", status = "completed", input = { pattern = "TODO" }, output = "matches" },
        }

        send_user_message(ai, "search for todos")
        local lines = get_chat_lines()

        local found = false
        for _, line in ipairs(lines) do
            if line:find("grep", 1, true) and line:find("TODO", 1, true) then
                found = true
                break
            end
        end
        assert(found, "Chat should contain tool use line with grep and pattern")
    end)

    it("renders multiple tool uses inline before response", function()
        stub_tool_uses = {
            { tool = "read", status = "completed", input = { filePath = "/workspace/a.lua" }, output = "a" },
            { tool = "read", status = "completed", input = { filePath = "/workspace/b.lua" }, output = "b" },
        }

        send_user_message(ai, "read both files")
        local lines = get_chat_lines()

        local tool_lines = 0
        for _, line in ipairs(lines) do
            if line:find("/workspace/a.lua", 1, true) or line:find("/workspace/b.lua", 1, true) then
                tool_lines = tool_lines + 1
            end
        end
        eq(tool_lines, 2, "Should have two tool use lines in the chat")
    end)

    it("tool use appears before the response text", function()
        stub_tool_uses = {
            { tool = "read", status = "completed", input = { filePath = "/workspace/foo.lua" }, output = "content" },
        }

        send_user_message(ai, "check the file")
        local lines = get_chat_lines()

        local tool_line_idx = nil
        local response_line_idx = nil
        for i, line in ipairs(lines) do
            if line:find("/workspace/foo.lua", 1, true) and not tool_line_idx then
                tool_line_idx = i
            end
            if line:find("The file contains useful code", 1, true) and not response_line_idx then
                response_line_idx = i
            end
        end
        assert(tool_line_idx, "Should find tool use line")
        assert(response_line_idx, "Should find response line")
        assert(tool_line_idx < response_line_idx, "Tool use should appear before response text")
    end)

    it("renders arrow style with tool name and target", function()
        stub_tool_uses = {
            { tool = "read", status = "completed", input = { filePath = "/workspace/foo.lua" }, output = "content" },
        }

        send_user_message(ai, "check the file")
        local lines = get_chat_lines()

        local found_arrow = false
        for _, line in ipairs(lines) do
            if line:find("> read /workspace/foo.lua", 1, true) then
                found_arrow = true
                break
            end
        end
        assert(found_arrow, "Should render tool use with arrow style: > read /path")
    end)

    it("no tool use lines when no tools are called", function()
        stub_tool_uses = nil

        send_user_message(ai, "simple question")
        local lines = get_chat_lines()

        for _, line in ipairs(lines) do
            assert(not line:find("read", 1, true) or line:find("read", 1, true) and not line:find("/workspace", 1, true),
                "Should not have tool use lines when no tools were called")
        end
        assert(chat_contains("The file contains useful code"), "Should still have response")
    end)
end)
