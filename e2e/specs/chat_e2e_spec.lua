-- e2e/specs/chat_e2e_spec.lua
-- End-to-end tests: real provider pipeline with mock servers/CLI

local ai = require("utils.ai")
local chat = require("utils.ai.chat")
local debug_mod = require("utils.ai.debug")

-- Suppress debug logs during tests
debug_mod.set_log_dir(vim.fn.tempname())

local function wait_for_response(timeout_ms)
    timeout_ms = timeout_ms or 5000
    vim.wait(timeout_ms, function()
        return not chat.is_streaming()
    end, 50)
end

local function get_chat_lines()
    local state = chat.get_state()
    if not state.buf_id or not vim.api.nvim_buf_is_valid(state.buf_id) then
        return {}
    end
    return vim.api.nvim_buf_get_lines(state.buf_id, 0, -1, false)
end

local function lines_contain(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

describe("e2e: opencode provider chat", function()
    before_each(function()
        ai.reset_all()
        -- Unset AI_WORK so opencode is the default provider
        vim.fn.setenv("AI_WORK", nil)

        ai.setup({})
        ai.activate()
    end)

    after_each(function()
        ai.reset_all()
    end)

    it("streams a response and renders it in the chat buffer", function()
        ai.send("e2e test message")
        wait_for_response()
        local lines = get_chat_lines()

        assert(#lines > 0, "chat buffer should have content")
        assert(lines_contain(lines, "You:"), "should have user header")
        assert(lines_contain(lines, "e2e test message"), "should have user message")
        assert(lines_contain(lines, "Assistant:"), "should have assistant header")
        assert(lines_contain(lines, "Hello from the mock CLI."), "should have assistant response")
    end)

    it("stores the response in conversation history", function()
        ai.send("e2e test message")
        wait_for_response()
        local session = ai.get_session()

        assert.equals(2, #session.conversation, "should have 2 messages (user + assistant)")
        assert.equals("user", session.conversation[1].role, "first message should be user")
        assert.equals("assistant", session.conversation[2].role, "second message should be assistant")
        assert(session.conversation[2].content:find("Hello from the mock CLI"),
            "assistant content should contain response")
    end)

    it("is not streaming after response completes", function()
        ai.send("e2e test message")
        wait_for_response()

        assert.equals(false, chat.is_streaming(), "should not be streaming after completion")
    end)

    it("renders tool use inline without error", function()
        ai.send("e2e tool use test")
        wait_for_response()
        local lines = get_chat_lines()

        assert(lines_contain(lines, "Found 3 files"), "should have assistant response after tool use")
        assert(lines_contain(lines, "list"), "should have tool use line with tool name")
    end)
end)
