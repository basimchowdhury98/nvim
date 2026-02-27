local eq = assert.are.same

local debug = require("utils.ai.debug")
local test_log_dir = vim.fn.stdpath("log") .. "/ai/tests"
debug.set_log_dir(test_log_dir)

local providers_mod = require("utils.ai.providers")

describe("AI Provider Contract", function()
    local provider_names = providers_mod.list()

    it("lists all registered providers", function()
        assert(#provider_names >= 3, "Should have at least 3 providers, got " .. #provider_names)
        local lookup = {}
        for _, name in ipairs(provider_names) do
            lookup[name] = true
        end
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
        -- Stub stream on all providers so we can verify delegation
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

        -- Restore
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

        -- Verify the callbacks are wired to the original functions
        captured_callbacks.on_delta("test")
        assert(delta_called, "on_delta should be wired to the caller's function")

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
