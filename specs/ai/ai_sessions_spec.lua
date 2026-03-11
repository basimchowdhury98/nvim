local eq = assert.are.same

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

describe("AI Session Helpers", function()
    local sessions = require("utils.ai.sessions")

    it("first_user_text extracts text from first user message", function()
        local messages = {
            {
                info = { role = "user" },
                parts = { { type = "text", text = "hello world" } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "hi there" } },
            },
        }

        local result = sessions._first_user_text(messages)

        eq("hello world", result, "Should extract text from first user message")
    end)

    it("first_user_text returns nil when no user messages exist", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "hi" } },
            },
        }

        local result = sessions._first_user_text(messages)

        eq(nil, result, "Should return nil when no user messages")
    end)

    it("first_user_text skips non-text parts", function()
        local messages = {
            {
                info = { role = "user" },
                parts = {
                    { type = "file", url = "foo.png" },
                    { type = "text", text = "look at this" },
                },
            },
        }

        local result = sessions._first_user_text(messages)

        eq("look at this", result, "Should skip non-text parts and find the text part")
    end)

    it("first_user_text returns nil for empty messages array", function()
        local result = sessions._first_user_text({})

        eq(nil, result, "Should return nil for empty array")
    end)

    it("messages_to_conversation converts opencode messages to conversation format", function()
        local messages = {
            {
                info = { role = "user" },
                parts = { { type = "text", text = "what is lua" } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "A programming language" } },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(2, #conv, "Should have 2 conversation entries")
        eq({ role = "user", content = "what is lua" }, conv[1], "First should be user message")
        eq({ role = "assistant", content = "A programming language" }, conv[2], "Second should be assistant message")
    end)

    it("messages_to_conversation joins multiple text parts with newline", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = {
                    { type = "text", text = "line one" },
                    { type = "text", text = "line two" },
                },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(1, #conv, "Should have 1 entry")
        eq("line one\nline two", conv[1].content, "Should join text parts with newline")
    end)

    it("messages_to_conversation skips non-text parts", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = {
                    { type = "tool", tool = "read", state = {} },
                    { type = "text", text = "the answer" },
                    { type = "step-finish", tokens = {} },
                },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(1, #conv, "Should have 1 entry")
        eq("the answer", conv[1].content, "Should only include text parts")
    end)

    it("messages_to_conversation handles empty messages array", function()
        local conv = sessions._messages_to_conversation({})

        eq({}, conv, "Should return empty conversation")
    end)

    it("messages_to_conversation keeps tool-only messages with tool_uses", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = { { type = "tool", tool = "read", state = { input = { filePath = "/foo.lua" } } } },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(1, #conv, "Should keep the entry for tool_uses")
        eq("read", conv[1].tool_uses[1].tool, "Should capture the tool name")
    end)

    it("messages_to_conversation merges consecutive assistant messages", function()
        local messages = {
            {
                info = { role = "user" },
                parts = { { type = "text", text = "hello" } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "Let me check." } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "Here is the answer." } },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(2, #conv, "Should merge consecutive assistant messages into one")
        eq("Let me check.\n\nHere is the answer.", conv[2].content,
            "Merged content should be joined with double newline")
    end)

    it("messages_to_conversation does not merge assistant messages split by user", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "first response" } },
            },
            {
                info = { role = "user" },
                parts = { { type = "text", text = "follow up" } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "second response" } },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(3, #conv, "Should keep separate when interleaved with user")
        eq("first response", conv[1].content, "First assistant message")
        eq("second response", conv[3].content, "Second assistant message")
    end)

    it("relative_time formats recent timestamps", function()
        local now = os.time()

        eq("just now", sessions._relative_time(now), "Should show 'just now' for current time")
        eq("just now", sessions._relative_time(now - 30), "Should show 'just now' for 30s ago")
    end)

    it("relative_time formats minutes ago", function()
        local now = os.time()

        local result = sessions._relative_time(now - 120)

        eq("2m ago", result, "Should show minutes ago")
    end)

    it("relative_time formats hours ago", function()
        local now = os.time()

        local result = sessions._relative_time(now - 7200)

        eq("2h ago", result, "Should show hours ago")
    end)

    it("relative_time formats days ago", function()
        local now = os.time()

        local result = sessions._relative_time(now - 172800)

        eq("2d ago", result, "Should show days ago")
    end)

    it("relative_time formats old dates as YYYY-MM-DD", function()
        -- A date far in the past (2023-01-15)
        local old_ts = os.time({ year = 2023, month = 1, day = 15, hour = 12, min = 0, sec = 0 })

        local result = sessions._relative_time(old_ts)

        assert(result:match("^%d%d%d%d%-%d%d%-%d%d$"), "Should format as date: " .. result)
    end)

    it("strip_editor_context removes the metadata block from user text", function()
        local text = "EDITOR CONTEXT:\nProject: /foo\nOpen buffers: a.lua\n\nWhat is lua?"

        local result = sessions._strip_editor_context(text)

        eq("What is lua?", result, "Should strip the context block and return user text")
    end)

    it("strip_editor_context leaves text without context block unchanged", function()
        local text = "Just a normal question"

        local result = sessions._strip_editor_context(text)

        eq("Just a normal question", result, "Should return text unchanged when no context block")
    end)

    it("strip_editor_context handles context block with no trailing text", function()
        local text = "EDITOR CONTEXT:\nProject: /foo\n\n"

        local result = sessions._strip_editor_context(text)

        eq("", result, "Should return empty string when only context block exists")
    end)

    it("messages_to_conversation strips editor context from user messages", function()
        local messages = {
            {
                info = { role = "user" },
                parts = { { type = "text", text = "EDITOR CONTEXT:\nProject: /foo\nOpen buffers: a.lua\n\nWhat is lua?" } },
            },
            {
                info = { role = "assistant" },
                parts = { { type = "text", text = "A programming language" } },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq("What is lua?", conv[1].content, "User message should have context stripped")
        eq("A programming language", conv[2].content, "Assistant message should be unchanged")
    end)

    it("messages_to_conversation extracts tool uses from assistant messages", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = {
                    { type = "tool", tool = "read", state = { input = { filePath = "/foo.lua" }, title = "Read file" } },
                    { type = "tool", tool = "grep", state = { input = { pattern = "TODO" }, title = "Search" } },
                    { type = "text", text = "Found some TODOs" },
                },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(2, #conv[1].tool_uses, "Should have 2 tool uses")
        eq("read", conv[1].tool_uses[1].tool, "First tool should be read")
        eq("/foo.lua", conv[1].tool_uses[1].input.filePath, "Should preserve input")
    end)

    it("messages_to_conversation extracts thinking from reasoning parts", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = {
                    { type = "reasoning", text = "Let me think about this..." },
                    { type = "text", text = "The answer is 42" },
                },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq("Let me think about this...", conv[1].thinking, "Should extract thinking")
        eq("The answer is 42", conv[1].content, "Should still have text content")
    end)

    it("messages_to_conversation merges tool uses across consecutive assistant messages", function()
        local messages = {
            {
                info = { role = "assistant" },
                parts = {
                    { type = "tool", tool = "read", state = { input = { filePath = "/a.lua" } } },
                },
            },
            {
                info = { role = "assistant" },
                parts = {
                    { type = "tool", tool = "grep", state = { input = { pattern = "fn" } } },
                    { type = "text", text = "Found it" },
                },
            },
        }

        local conv = sessions._messages_to_conversation(messages)

        eq(1, #conv, "Should merge into one entry")
        eq(2, #conv[1].tool_uses, "Should have 2 tool uses from both messages")
        eq("Found it", conv[1].content, "Should have the text content")
    end)
end)

describe("AI Session Resume", function()
    local ai = require("utils.ai")
    local chat = require("utils.ai.chat")
    ai.setup()
    stub_api()
    vim.notify = function() end

    before_each(function()
        ai.reset_all()
        stub_api()
        stub_response = "I am a test response"
        stub_error = nil
        stream_messages_spy = nil
    end)

    after_each(function()
        close_all_floats()
    end)

    it("resume_session activates the system and loads conversation", function()
        local conversation = {
            { role = "user", content = "what is lua" },
            { role = "assistant", content = "A programming language" },
        }

        ai.resume_session("test-session-id", conversation)

        assert(ai.is_active(), "System should be active after resume")
    end)

    it("resume_session opens chat panel with conversation history", function()
        local conversation = {
            { role = "user", content = "what is lua" },
            { role = "assistant", content = "A programming language" },
        }

        ai.resume_session("test-session-id", conversation)

        assert(chat.is_open(), "Chat panel should be open")
        assert(chat_contains("what is lua"), "Chat should show user message")
        assert(chat_contains("A programming language"), "Chat should show assistant response")
    end)

    it("resume_session loads conversation into session for API continuity", function()
        local conversation = {
            { role = "user", content = "what is lua" },
            { role = "assistant", content = "A programming language" },
        }

        ai.resume_session("test-session-id", conversation)
        send_user_message(ai, "tell me more")

        assert(stream_messages_spy ~= nil, "Should have sent a message")
        eq(3, #stream_messages_spy, "API should get all 3 messages (2 resumed + 1 new)")
        assert(stream_messages_spy[3].content:find("tell me more", 1, true),
            "Last message should be the new one")
    end)

    it("resume_session sets opencode session ID", function()
        local opencode = require("utils.ai.providers.opencode")

        ai.resume_session("my-session-123", {
            { role = "user", content = "hello" },
            { role = "assistant", content = "hi" },
        })

        eq("my-session-123", opencode.get_session_id(), "Opencode session ID should be set")
    end)

    it("resume_session replaces any active session", function()
        ai.activate()
        send_user_message(ai, "first session message")

        ai.resume_session("new-session-id", {
            { role = "user", content = "resumed question" },
            { role = "assistant", content = "resumed answer" },
        })

        assert(ai.is_active(), "Should still be active")
        assert(chat_contains("resumed question"), "Chat should show resumed conversation")
        assert(not chat_contains("first session message"), "Old conversation should be cleared")
    end)

    it("resume_session with empty conversation opens an empty chat", function()
        ai.resume_session("empty-session", {})

        assert(ai.is_active(), "System should be active")
        assert(chat.is_open(), "Chat should be open")
    end)

    it("can send messages after resuming a session", function()
        ai.resume_session("test-session", {
            { role = "user", content = "previous question" },
            { role = "assistant", content = "previous answer" },
        })

        send_user_message(ai, "follow up question")

        assert(chat_contains("follow up question"), "New message should appear in chat")
        assert(chat_contains(stub_response), "Response should appear in chat")
    end)

    it("stop after resume deactivates cleanly", function()
        ai.resume_session("test-session", {
            { role = "user", content = "hello" },
            { role = "assistant", content = "hi" },
        })

        ai.stop()

        assert(not ai.is_active(), "System should be inactive after stop")
        assert(not chat.is_open(), "Chat should be closed after stop")
    end)

    it("context dump includes resumed conversation", function()
        ai.resume_session("test-session", {
            { role = "user", content = "what is lua" },
            { role = "assistant", content = "A programming language" },
        })

        local snapshot = ai.build_state_snapshot()

        eq(2, #snapshot.conversation, "Snapshot should have 2 messages from resumed session")
        eq("what is lua", snapshot.conversation[1].content, "First message should be user text")
    end)

    it("resume_session renders tool uses in chat panel", function()
        ai.resume_session("test-session", {
            { role = "user", content = "check the code" },
            { role = "assistant", content = "Looks good", tool_uses = {
                { tool = "read", input = { filePath = "/workspace/foo.lua" } },
            }},
        })

        assert(chat_contains("> read"), "Chat should show tool use indicator")
        assert(chat_contains("Looks good"), "Chat should show response text")
    end)

    it("resume_session renders collapsed thinking in chat panel", function()
        ai.resume_session("test-session", {
            { role = "user", content = "explain this" },
            { role = "assistant", content = "Here is the explanation", thinking = "Let me analyze..." },
        })

        assert(chat_contains("Thinking..."), "Chat should show collapsed thinking indicator")
        assert(chat_contains("Here is the explanation"), "Chat should show response text")
    end)

    it("context dump includes tool uses in conversation", function()
        ai.resume_session("test-session", {
            { role = "user", content = "check code" },
            { role = "assistant", content = "Looks good", tool_uses = {
                { tool = "read", input = { filePath = "/foo.lua" } },
            }},
        })

        local snapshot = ai.build_state_snapshot()
        local debug_mod = require("utils.ai.debug")
        local dump = debug_mod.format_snapshot(snapshot)

        assert(dump:find("> read /foo.lua", 1, true), "Dump should include tool use line")
    end)

    it("stores tool uses in conversation during streaming", function()
        local tool_spy = nil
        api.stream = function(_messages, on_delta, on_done, _, opts)
            if opts and opts.on_tool_use then
                opts.on_tool_use({ tool = "read", input = { filePath = "/bar.lua" }, status = "completed" })
            end
            on_delta("response text")
            on_done()
            tool_spy = true
            return function() end
        end

        send_user_message(ai, "check it")
        local session = ai.get_session()
        local last_msg = session.conversation[#session.conversation]

        assert(tool_spy, "Tool use callback should have fired")
        assert(last_msg.tool_uses, "Assistant message should have tool_uses")
        eq("read", last_msg.tool_uses[1].tool, "Should store the tool name")
    end)
end)
