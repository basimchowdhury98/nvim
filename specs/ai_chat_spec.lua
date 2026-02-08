local eq = assert.are.same

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

local function find_float()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= "" then
            return win, vim.api.nvim_win_get_buf(win)
        end
    end
    return nil, nil
end

local function close_all_floats()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= "" then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
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
    ai.prompt()
    local _, input_buf = find_float()
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
        ai.prompt()

        local float_win = find_float()
        assert(float_win ~= nil, "Input float should be open")
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
        send_user_message(ai, "hello")

        assert(find_float() == nil, "Input popup should be closed after sending")
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

    it("passes conversation history to the api", function()
        send_user_message(ai, "first")
        stub_response = "reply two"

        send_user_message(ai, "second")

        local n = #stream_messages_spy
        eq(stream_messages_spy[n].role, "user")
        assert(stream_messages_spy[n].content:find("second"), "Last message should be 'second'")
        eq(stream_messages_spy[n - 1].role, "assistant")
        eq(stream_messages_spy[n - 2].role, "user")
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

    it("clear on empty state does nothing harmful", function()
        ai.clear()
        ai.clear()
    end)
end)

describe("AI Debug", function()
    local debug = require("utils.ai.debug")

    before_each(function()
        if debug.is_enabled() then
            debug.toggle()
        end
    end)

    it("starts with debug disabled", function()
        assert(not debug.is_enabled())
    end)

    it("toggles debug on and off", function()
        debug.toggle()
        assert(debug.is_enabled())

        debug.toggle()
        assert(not debug.is_enabled())
    end)

    it("log only prints when enabled", function()
        local orig_print = print
        local printed = nil
        print = function(msg) printed = msg end

        debug.log("should not appear")

        assert(printed == nil, "Should not print when debug is off")

        debug.toggle()
        debug.log("should appear")

        assert(printed ~= nil and printed:find("should appear"), "Should print when debug is on")
        print = orig_print
    end)
end)
