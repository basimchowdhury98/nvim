local eq = assert.are.same

local debug = require("utils.ai.debug")
local test_log_dir = vim.fn.stdpath("log") .. "/ai/tests"
debug.set_log_dir(test_log_dir)

local providers_mod = require("utils.ai.providers")

describe("AI Provider Contract", function()
    local provider_names = providers_mod.list()

    it("lists all registered providers", function()
        local lookup = {}
        for _, name in ipairs(provider_names) do
            lookup[name] = true
        end

        assert(#provider_names >= 2, "Should have at least 2 providers, got " .. #provider_names)
        assert(lookup["opencode"], "Should include opencode provider")
        assert(lookup["anthropic"], "Should include anthropic provider")
    end)

    for _, name in ipairs(provider_names) do
        it(name .. " has a name field", function()
            local provider = providers_mod.get(name)

            eq(type(provider.name), "string", name .. " provider.name should be a string")
            eq(provider.name, name, name .. " provider.name should match the registry key")
        end)

        it(name .. " has a stream function", function()
            local provider = providers_mod.get(name)

            eq(type(provider.stream), "function", name .. " provider.stream should be a function")
        end)
    end

    it("get errors on unknown provider", function()
        local ok, err = pcall(providers_mod.get, "nonexistent")

        assert(not ok, "Should error on unknown provider")
        assert(tostring(err):find("unknown provider"), "Error should mention unknown provider")
    end)

    it("get caches validated providers", function()
        local p1 = providers_mod.get("opencode")
        local p2 = providers_mod.get("opencode")

        assert(rawequal(p1, p2), "get() should return the same table reference on repeated calls")
    end)
end)

describe("AI Provider Streaming", function()
    -- These tests verify that each provider's stream() function follows the
    -- callback contract: it calls on_error when config is missing/invalid,
    -- and returns nil (no cancel function) on setup failures.
    -- We do NOT call real APIs — we test the validation/error paths.

    it("anthropic calls on_error when api_key is missing", function()
        local provider = providers_mod.get("anthropic")
        local error_msg = nil

        local cancel = provider.stream(
            { { role = "user", content = "hello" } },
            { system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        assert(cancel == nil, "Should return nil when api_key is missing")
        assert(error_msg, "Should have called on_error")
        assert(error_msg:find("API key"), "Error should mention API key, got: " .. error_msg)
    end)

end)

describe("AI Provider SSE Parsing", function()
    local job = require("utils.ai.job")
    local original_run = job.run
    local original_write_temp = job.write_temp
    local original_curl_sync = job.curl_sync
    local original_schedule = vim.schedule

    before_each(function()
        -- Mock vim.schedule to execute immediately (incidental async wrapper)
        vim.schedule = function(fn) fn() end
        -- Mock write_temp to avoid file I/O
        job.write_temp = function() return "/tmp/fake", nil end
    end)

    after_each(function()
        job.run = original_run
        job.write_temp = original_write_temp
        job.curl_sync = original_curl_sync
        vim.schedule = original_schedule
    end)

    it("anthropic parses content_block_delta into on_delta", function()
        local provider = providers_mod.get("anthropic")
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}')
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}')
            opts.on_stdout('data: {"type":"message_stop"}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
            }
        )

        eq(deltas, { "hello", " world" }, "Should have received both text deltas")
        assert(done, "on_done should have been called on message_stop")
    end)

    it("anthropic parses error events into on_error", function()
        local provider = providers_mod.get("anthropic")
        local error_msg = nil
        job.run = function(opts)
            opts.on_stdout('data: {"type":"error","error":{"message":"rate limited"}}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        eq(error_msg, "rate limited", "Should have parsed the error message")
    end)

    it("anthropic parses non-SSE JSON error responses", function()
        local provider = providers_mod.get("anthropic")
        local error_msg = nil
        job.run = function(opts)
            opts.on_stdout('{"type":"error","error":{"message":"invalid api key"}}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        eq(error_msg, "invalid api key", "Should have parsed the JSON error response")
    end)

    it("anthropic ignores non-text SSE events", function()
        local provider = providers_mod.get("anthropic")
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message_start","message":{"id":"msg_123"}}')
            opts.on_stdout('data: {"type":"content_block_start","content_block":{"type":"text"}}')
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"actual"}}')
            opts.on_stdout('data: {"type":"content_block_stop"}')
            opts.on_stdout('data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}')
            opts.on_stdout('data: {"type":"message_stop"}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
            }
        )

        eq(deltas, { "actual" }, "Should only capture text deltas, not other event types")
        assert(done, "on_done should have been called")
    end)

    it("anthropic parses thinking_delta into on_thinking", function()
        local provider = providers_mod.get("anthropic")
        local thinking_chunks = {}
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"I need to"}}')
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":" think about this"}}')
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Here is my answer"}}')
            opts.on_stdout('data: {"type":"message_stop"}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
                on_thinking = function(text) table.insert(thinking_chunks, text) end,
            }
        )

        eq(thinking_chunks, { "I need to", " think about this" }, "Should have received thinking deltas")
        eq(deltas, { "Here is my answer" }, "Should have received text delta separately")
        assert(done, "on_done should have been called")
    end)

    it("anthropic ignores thinking_delta when on_thinking is nil", function()
        local provider = providers_mod.get("anthropic")
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"secret thoughts"}}')
            opts.on_stdout('data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"visible"}}')
            opts.on_stdout('data: {"type":"message_stop"}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "test-key", model = "test", endpoint = "http://localhost",
              api_version = "2023-06-01", system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
            }
        )

        eq(deltas, { "visible" }, "Should only have text deltas")
        assert(done, "on_done should have been called")
    end)

    it("opencode parses text delta SSE events into on_delta", function()
        local opencode = require("utils.ai.providers.opencode")
        local deltas = {}
        local done_metadata = nil
        local sid = "test-session-1"
        opencode.clear_session()
        job.curl_sync = function(cmd)
            local cmd_str = table.concat(cmd, " ")
            if cmd_str:find("/global/health") then return '{"healthy":true,"version":"test"}', nil
            elseif cmd_str:find("/prompt_async") then return "", nil
            elseif cmd_str:find("POST") then return '{"id":"' .. sid .. '"}', nil
            end
            return "", nil
        end
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"text"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"hello","field":"text"}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":" world","field":"text"}}')
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"step-finish","tokens":{"input":42,"output":5,"reasoning":0,"cache":{"read":10,"write":2}},"cost":0.001}}}')
            opts.on_stdout('data: {"type":"session.idle","properties":{"sessionID":"' .. sid .. '"}}')
            return function() end
        end

        providers_mod.get("opencode").stream(
            { { role = "user", content = "test" } },
            { system_prompt = "test", max_tokens = 100, port = 99999 },
            { on_delta = function(text) table.insert(deltas, text) end,
              on_done = function(meta) done_metadata = meta end,
              on_error = function() end }
        )

        eq(deltas, { "hello", " world" }, "Should have received both text deltas")
        assert(done_metadata, "on_done should have been called with metadata")
        eq(done_metadata.tokens.input, 42, "Should have parsed input tokens")
        eq(done_metadata.tokens.cache_read, 10, "Should have parsed cache read tokens")
        opencode.clear_session()
    end)

    it("opencode parses tool_use SSE events into on_tool_use", function()
        local opencode = require("utils.ai.providers.opencode")
        local deltas = {}
        local tool_uses = {}
        local done = false
        local sid = "test-session-2"
        opencode.clear_session()
        job.curl_sync = function(cmd)
            local cmd_str = table.concat(cmd, " ")
            if cmd_str:find("/global/health") then return '{"healthy":true,"version":"test"}', nil
            elseif cmd_str:find("/prompt_async") then return "", nil
            elseif cmd_str:find("POST") then return '{"id":"' .. sid .. '"}', nil
            end
            return "", nil
        end
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"tool","tool":"read","state":{"status":"completed","input":{"filePath":"/workspace/foo.lua"},"output":"local x = 1","title":"Read file","metadata":{},"time":{"start":1,"end":2}}}}}')
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"text"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"Here is the file.","field":"text"}}')
            opts.on_stdout('data: {"type":"session.idle","properties":{"sessionID":"' .. sid .. '"}}')
            return function() end
        end

        providers_mod.get("opencode").stream(
            { { role = "user", content = "test" } },
            { system_prompt = "test", max_tokens = 100, port = 99999 },
            { on_delta = function(text) table.insert(deltas, text) end,
              on_done = function() done = true end,
              on_error = function() end,
              on_tool_use = function(info) table.insert(tool_uses, vim.deepcopy(info)) end }
        )

        eq(#tool_uses, 1, "Should have received one tool_use event")
        eq(tool_uses[1].tool, "read", "Tool name should be 'read'")
        eq(tool_uses[1].status, "completed", "Tool status should be 'completed'")
        eq(deltas, { "Here is the file." }, "Should have received text delta after tool use")
        assert(done, "on_done should have been called")
        opencode.clear_session()
    end)

    it("opencode parses reasoning SSE events into on_thinking", function()
        local opencode = require("utils.ai.providers.opencode")
        local deltas = {}
        local thinking_chunks = {}
        local done = false
        local sid = "test-session-3"
        opencode.clear_session()
        job.curl_sync = function(cmd)
            local cmd_str = table.concat(cmd, " ")
            if cmd_str:find("/global/health") then return '{"healthy":true,"version":"test"}', nil
            elseif cmd_str:find("/prompt_async") then return "", nil
            elseif cmd_str:find("POST") then return '{"id":"' .. sid .. '"}', nil
            end
            return "", nil
        end
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"reasoning"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"I need to think","field":"text"}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":" about this","field":"text"}}')
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"text"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"Answer","field":"text"}}')
            opts.on_stdout('data: {"type":"session.idle","properties":{"sessionID":"' .. sid .. '"}}')
            return function() end
        end

        providers_mod.get("opencode").stream(
            { { role = "user", content = "test" } },
            { system_prompt = "test", max_tokens = 100, port = 99999 },
            { on_delta = function(text) table.insert(deltas, text) end,
              on_done = function() done = true end,
              on_error = function() end,
              on_thinking = function(text) table.insert(thinking_chunks, text) end }
        )

        eq(thinking_chunks, { "I need to think", " about this" }, "Should have received thinking deltas")
        eq(deltas, { "Answer" }, "Should have received text delta separately")
        assert(done, "on_done should have been called")
        opencode.clear_session()
    end)

    it("opencode filters SSE events by session ID", function()
        local opencode = require("utils.ai.providers.opencode")
        local deltas = {}
        local done = false
        local sid = "test-session-4"
        opencode.clear_session()
        job.curl_sync = function(cmd)
            local cmd_str = table.concat(cmd, " ")
            if cmd_str:find("/global/health") then return '{"healthy":true,"version":"test"}', nil
            elseif cmd_str:find("/prompt_async") then return "", nil
            elseif cmd_str:find("POST") then return '{"id":"' .. sid .. '"}', nil
            end
            return "", nil
        end
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"other-session","delta":"wrong","field":"text"}}')
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"text"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"right","field":"text"}}')
            opts.on_stdout('data: {"type":"session.idle","properties":{"sessionID":"' .. sid .. '"}}')
            return function() end
        end

        providers_mod.get("opencode").stream(
            { { role = "user", content = "test" } },
            { system_prompt = "test", max_tokens = 100, port = 99999 },
            { on_delta = function(text) table.insert(deltas, text) end,
              on_done = function() done = true end,
              on_error = function() end }
        )

        eq(deltas, { "right" }, "Should only receive deltas from our session")
        assert(done, "on_done should have been called")
        opencode.clear_session()
    end)

    it("opencode calls on_error when server is unreachable", function()
        local opencode = require("utils.ai.providers.opencode")
        local error_msg = nil
        local original_wait = vim.wait
        local original_jobstart = vim.fn.jobstart
        opencode.clear_session()
        vim.wait = function() end
        job.curl_sync = function() return nil, "connection refused" end
        vim.fn.jobstart = function() return 1 end

        local cancel = providers_mod.get("opencode").stream(
            { { role = "user", content = "test" } },
            { system_prompt = "test", max_tokens = 100, port = 99999 },
            { on_delta = function() end, on_done = function() end,
              on_error = function(err) error_msg = err end }
        )

        assert(cancel == nil, "Should return nil when server is unreachable")
        assert(error_msg, "Should have called on_error")
        assert(error_msg:find("Failed to start opencode server"), "Error should mention server failure, got: " .. error_msg)
        vim.wait = original_wait
        vim.fn.jobstart = original_jobstart
        opencode.clear_session()
    end)

    it("opencode reuses session across multiple stream calls", function()
        local opencode = require("utils.ai.providers.opencode")
        local sid = "test-session-5"
        local create_session_calls = 0
        opencode.clear_session()
        job.curl_sync = function(cmd)
            local cmd_str = table.concat(cmd, " ")
            if cmd_str:find("/global/health") then return '{"healthy":true,"version":"test"}', nil
            elseif cmd_str:find("/prompt_async") then return "", nil
            elseif cmd_str:find("POST") then
                create_session_calls = create_session_calls + 1
                return '{"id":"' .. sid .. '"}', nil
            end
            return "", nil
        end
        job.run = function(opts)
            opts.on_stdout('data: {"type":"message.part.updated","properties":{"part":{"sessionID":"' .. sid .. '","type":"text"}}}')
            opts.on_stdout('data: {"type":"message.part.delta","properties":{"sessionID":"' .. sid .. '","delta":"ok","field":"text"}}')
            opts.on_stdout('data: {"type":"session.idle","properties":{"sessionID":"' .. sid .. '"}}')
            return function() end
        end

        local cfg = { system_prompt = "test", max_tokens = 100, port = 99999 }
        local cb = { on_delta = function() end, on_done = function() end, on_error = function() end }
        providers_mod.get("opencode").stream({ { role = "user", content = "first" } }, cfg, cb)
        providers_mod.get("opencode").stream({ { role = "user", content = "second" } }, cfg, cb)

        eq(create_session_calls, 1, "Should only create session once, reuse for second call")
        eq(opencode.get_session_id(), sid, "Should still have the same session ID")
        opencode.clear_session()
    end)

end)

describe("AI Provider Dispatcher", function()
    local api = require("utils.ai.api")

    it("get_provider returns opencode by default", function()
        local original = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)

        local provider = api.get_provider()

        eq(provider, "opencode", "Default provider should be opencode")
        vim.fn.setenv("AI_WORK", original)
    end)

    it("get_provider returns anthropic when AI_WORK is set", function()
        local original = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", "true")

        local provider = api.get_provider()

        eq(provider, "anthropic", "Provider should be anthropic in work mode")
        vim.fn.setenv("AI_WORK", original)
    end)

    it("stream delegates to the resolved provider", function()
        local called_provider = nil
        local original_streams = {}
        for _, name in ipairs(providers_mod.list()) do
            local p = providers_mod.get(name)
            original_streams[name] = p.stream
            p.stream = function(_, _, callbacks)
                called_provider = name
                callbacks.on_done()
                return function() end
            end
        end
        local original_env = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)

        api.stream(
            { { role = "user", content = "test" } },
            function() end,
            function() end,
            function() end
        )

        eq(called_provider, "opencode", "Should have called opencode provider")
        for _, name in ipairs(providers_mod.list()) do
            local p = providers_mod.get(name)
            p.stream = original_streams[name]
        end
        vim.fn.setenv("AI_WORK", original_env)
    end)

    it("stream passes callbacks correctly to provider", function()
        local captured_callbacks = nil
        local p = providers_mod.get("opencode")
        local original_stream = p.stream
        p.stream = function(_, _, callbacks)
            captured_callbacks = callbacks
            callbacks.on_done()
            return function() end
        end
        local original_env = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)
        local delta_called = false
        local done_called = false

        api.stream(
            { { role = "user", content = "test" } },
            function() delta_called = true end,
            function() done_called = true end,
            function() end
        )

        assert(captured_callbacks, "Provider should receive callbacks table")
        assert(type(captured_callbacks.on_delta) == "function", "Callbacks should include on_delta")
        assert(type(captured_callbacks.on_done) == "function", "Callbacks should include on_done")
        assert(type(captured_callbacks.on_error) == "function", "Callbacks should include on_error")
        captured_callbacks.on_delta("test")
        assert(delta_called, "on_delta should be wired to the caller's function")
        captured_callbacks.on_done("test")
        assert(done_called, "on_done should be wired to the caller's function")
        p.stream = original_stream
        vim.fn.setenv("AI_WORK", original_env)
    end)

    it("stream passes on_thinking callback to provider", function()
        local captured_callbacks = nil
        local p = providers_mod.get("opencode")
        local original_stream = p.stream
        p.stream = function(_, _, callbacks)
            captured_callbacks = callbacks
            callbacks.on_done()
            return function() end
        end
        local original_env = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)
        local thinking_called = false

        api.stream(
            { { role = "user", content = "test" } },
            function() end,
            function() end,
            function() end,
            { on_thinking = function() thinking_called = true end }
        )

        assert(captured_callbacks, "Provider should receive callbacks table")
        assert(type(captured_callbacks.on_thinking) == "function", "Callbacks should include on_thinking")
        captured_callbacks.on_thinking("test thought")
        assert(thinking_called, "on_thinking should be wired to the caller's function")
        p.stream = original_stream
        vim.fn.setenv("AI_WORK", original_env)
    end)

    it("stream passes provider config with system_prompt", function()
        local captured_config = nil
        local p = providers_mod.get("opencode")
        local original_stream = p.stream
        p.stream = function(_, cfg, callbacks)
            captured_config = cfg
            callbacks.on_done()
            return function() end
        end
        local original_env = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", vim.NIL)

        api.stream(
            { { role = "user", content = "test" } },
            function() end,
            function() end,
            function() end
        )

        assert(captured_config, "Provider should receive config")
        assert(captured_config.system_prompt, "Config should include system_prompt")
        assert(captured_config.max_tokens, "Config should include max_tokens")
        assert(captured_config.port, "Config should include port for opencode")
        p.stream = original_stream
        vim.fn.setenv("AI_WORK", original_env)
    end)
end)
