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

        assert(#provider_names >= 3, "Should have at least 3 providers, got " .. #provider_names)
        assert(lookup["opencode"], "Should include opencode provider")
        assert(lookup["anthropic"], "Should include anthropic provider")
        assert(lookup["alt"], "Should include alt provider")
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

    it("alt calls on_error when endpoint is missing", function()
        local provider = providers_mod.get("alt")
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

        assert(cancel == nil, "Should return nil when alt is not configured")
        assert(error_msg, "Should have called on_error")
        assert(error_msg:find("not configured"), "Error should mention not configured, got: " .. error_msg)
    end)

    it("alt calls on_error when api_key is missing", function()
        local provider = providers_mod.get("alt")
        local error_msg = nil

        local cancel = provider.stream(
            { { role = "user", content = "hello" } },
            { system_prompt = "test", max_tokens = 100, endpoint = "http://localhost", model = "test" },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        assert(cancel == nil, "Should return nil when api_key is missing")
        assert(error_msg, "Should have called on_error")
        assert(error_msg:find("not configured"), "Error should mention not configured, got: " .. error_msg)
    end)

    it("alt calls on_error when model is missing", function()
        local provider = providers_mod.get("alt")
        local error_msg = nil

        local cancel = provider.stream(
            { { role = "user", content = "hello" } },
            { system_prompt = "test", max_tokens = 100, endpoint = "http://localhost", api_key = "key" },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        assert(cancel == nil, "Should return nil when model is missing")
        assert(error_msg, "Should have called on_error")
        assert(error_msg:find("not configured"), "Error should mention not configured, got: " .. error_msg)
    end)
end)

describe("AI Provider SSE Parsing", function()
    local job = require("utils.ai.job")
    local original_run = job.run
    local original_write_temp = job.write_temp
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

    it("alt parses OpenAI-style SSE deltas into on_delta", function()
        local provider = providers_mod.get("alt")
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"choices":[{"delta":{"content":"foo"}}]}')
            opts.on_stdout('data: {"choices":[{"delta":{"content":"bar"}}]}')
            opts.on_stdout("data: [DONE]")
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "key", model = "m", endpoint = "http://localhost",
              system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
            }
        )

        eq(deltas, { "foo", "bar" }, "Should have received both deltas")
        assert(done, "on_done should have been called on [DONE]")
    end)

    it("alt parses JSON error responses", function()
        local provider = providers_mod.get("alt")
        local error_msg = nil
        job.run = function(opts)
            opts.on_stdout('{"error":{"message":"bad request"}}')
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "key", model = "m", endpoint = "http://localhost",
              system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function() end,
                on_done = function() end,
                on_error = function(err) error_msg = err end,
            }
        )

        eq(error_msg, "bad request", "Should have parsed the error message")
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

    it("alt parses think tags into on_thinking", function()
        local provider = providers_mod.get("alt")
        local thinking_chunks = {}
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"choices":[{"delta":{"content":"<think>I am thinking"}}]}')
            opts.on_stdout('data: {"choices":[{"delta":{"content":" more thoughts</think>"}}]}')
            opts.on_stdout('data: {"choices":[{"delta":{"content":"The answer is 42"}}]}')
            opts.on_stdout("data: [DONE]")
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "key", model = "m", endpoint = "http://localhost",
              system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
                on_thinking = function(text) table.insert(thinking_chunks, text) end,
            }
        )

        eq(thinking_chunks, { "I am thinking", " more thoughts" }, "Should have received thinking from think tags")
        eq(deltas, { "The answer is 42" }, "Should have received text after think tags")
        assert(done, "on_done should have been called")
    end)

    it("alt parses reasoning_content into on_thinking", function()
        local provider = providers_mod.get("alt")
        local thinking_chunks = {}
        local deltas = {}
        local done = false
        job.run = function(opts)
            opts.on_stdout('data: {"choices":[{"delta":{"reasoning_content":"step 1"}}]}')
            opts.on_stdout('data: {"choices":[{"delta":{"reasoning_content":" then step 2"}}]}')
            opts.on_stdout('data: {"choices":[{"delta":{"content":"final answer"}}]}')
            opts.on_stdout("data: [DONE]")
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "key", model = "m", endpoint = "http://localhost",
              system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() done = true end,
                on_error = function() end,
                on_thinking = function(text) table.insert(thinking_chunks, text) end,
            }
        )

        eq(thinking_chunks, { "step 1", " then step 2" }, "Should have received reasoning_content as thinking")
        eq(deltas, { "final answer" }, "Should have received content as delta")
        assert(done, "on_done should have been called")
    end)

    it("alt handles think tags in a single chunk", function()
        local provider = providers_mod.get("alt")
        local thinking_chunks = {}
        local deltas = {}
        job.run = function(opts)
            opts.on_stdout('data: {"choices":[{"delta":{"content":"<think>quick thought</think>answer"}}]}')
            opts.on_stdout("data: [DONE]")
            opts.on_exit(0, "")
            return function() end
        end

        provider.stream(
            { { role = "user", content = "test" } },
            { api_key = "key", model = "m", endpoint = "http://localhost",
              system_prompt = "test", max_tokens = 100 },
            {
                on_delta = function(text) table.insert(deltas, text) end,
                on_done = function() end,
                on_error = function() end,
                on_thinking = function(text) table.insert(thinking_chunks, text) end,
            }
        )

        eq(thinking_chunks, { "quick thought" }, "Should parse thinking from single chunk")
        eq(deltas, { "answer" }, "Should parse content after closing think tag")
    end)
end)

describe("AI Provider Dispatcher", function()
    local api = require("utils.ai.api")

    before_each(function()
        api.reset_alt()
    end)

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

    it("get_provider returns alt when AI_WORK is set and alt mode toggled", function()
        local original = vim.fn.getenv("AI_WORK")
        vim.fn.setenv("AI_WORK", "true")

        api.toggle_alt()
        local provider = api.get_provider()

        eq(provider, "alt", "Provider should be alt after toggle")
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
        p.stream = original_stream
        vim.fn.setenv("AI_WORK", original_env)
    end)
end)
