local eq = assert.are.same
local usage = require("utils.ai.usage")
local lag = require("utils.ai.lag")

describe("AI Usage Tracking", function()
    before_each(function()
        usage.reset()
        lag.reset()
    end)

    it("starts with zero totals", function()
        local totals = usage.get_totals()

        eq(0, totals.input, "Input tokens should start at zero")
        eq(0, totals.output, "Output tokens should start at zero")
        eq(0, totals.requests, "Request count should start at zero")
    end)

    it("accumulates token counts from metadata", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 200, cache_write = 10 } })
        usage.add({ tokens = { input = 150, output = 75, cache_read = 0, cache_write = 0 } })

        local totals = usage.get_totals()

        eq(250, totals.input, "Input tokens should accumulate")
        eq(125, totals.output, "Output tokens should accumulate")
        eq(200, totals.cache_read, "Cache read should accumulate")
        eq(10, totals.cache_write, "Cache write should accumulate")
        eq(2, totals.requests, "Request count should be 2")
    end)

    it("accumulates cost", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 }, cost = 0.05 })
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 }, cost = 0.03 })

        local totals = usage.get_totals()

        eq(0.08, totals.cost, "Cost should accumulate")
    end)

    it("ignores nil metadata", function()
        usage.add(nil)

        local totals = usage.get_totals()

        eq(0, totals.requests, "Nil metadata should not increment request count")
    end)

    it("handles metadata without tokens", function()
        usage.add({ cost = 0.01 })

        local totals = usage.get_totals()

        eq(1, totals.requests, "Should count request even without tokens")
        eq(0, totals.input, "Input should remain zero")
        eq(0.01, totals.cost, "Cost should still accumulate")
    end)

    it("handles metadata without cost", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local totals = usage.get_totals()

        eq(1, totals.requests, "Should count request")
        eq(0, totals.cost, "Cost should remain zero")
    end)

    it("reset clears all totals", function()
        usage.add({ tokens = { input = 500, output = 200, cache_read = 100, cache_write = 50 }, cost = 0.10 })

        usage.reset()

        local totals = usage.get_totals()
        eq(0, totals.input, "Input should be zero after reset")
        eq(0, totals.output, "Output should be zero after reset")
        eq(0, totals.cache_read, "Cache read should be zero after reset")
        eq(0, totals.cost, "Cost should be zero after reset")
        eq(0, totals.requests, "Requests should be zero after reset")
    end)

    it("has_data returns false when empty", function()
        local result = usage.has_data()

        assert(not result, "Should have no data initially")
    end)

    it("has_data returns true after adding metadata", function()
        usage.add({ tokens = { input = 1, output = 1, cache_read = 0, cache_write = 0 } })

        assert(usage.has_data(), "Should have data after add")
    end)
end)

describe("AI Usage Formatting", function()
    before_each(function()
        usage.reset()
        lag.reset()
    end)

    it("format_tokens shows raw number below 1K", function()
        local result = usage._format_tokens(500)

        eq("500", result, "Should show raw number")
    end)

    it("format_tokens shows K suffix for thousands", function()
        local result = usage._format_tokens(1200)

        eq("1.2K", result, "Should format as K")
    end)

    it("format_tokens shows M suffix for millions", function()
        local result = usage._format_tokens(1500000)

        eq("1.5M", result, "Should format as M")
    end)

    it("format_stats returns empty string when no data", function()
        local result = usage.format_stats()

        eq("", result, "Should be empty with no data")
    end)

    it("format_stats shows input and output", function()
        usage.add({ tokens = { input = 1200, output = 300, cache_read = 0, cache_write = 0 } })

        local stats = usage.format_stats()

        assert(stats:find("1.2K in"), "Should contain input: " .. stats)
        assert(stats:find("300 out"), "Should contain output: " .. stats)
    end)

    it("format_stats includes cache when present", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 5000, cache_write = 0 } })

        local stats = usage.format_stats()

        assert(stats:find("5.0K cached"), "Should contain cache: " .. stats)
    end)

    it("format_stats includes cost when present", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 }, cost = 0.15 })

        local stats = usage.format_stats()

        assert(stats:find("$0.15"), "Should contain cost: " .. stats)
    end)

    it("format_stats omits cache when zero", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local stats = usage.format_stats()

        assert(not stats:find("cached"), "Should not contain cache: " .. stats)
    end)

    it("format_stats omits cost when zero", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local stats = usage.format_stats()

        assert(not stats:find("%$"), "Should not contain cost: " .. stats)
    end)
end)

describe("AI Usage Tabline", function()
    before_each(function()
        usage.reset()
        lag.reset()
    end)

    it("returns empty tabline when no lag and no usage", function()
        local result = usage.build_tabline()

        eq("", result, "Should be empty")
    end)

    it("shows Lag label when lag is running with no usage", function()
        lag.start(function() end, function() return { conversation = {} } end)

        local tabline = usage.build_tabline()

        assert(tabline:find("Lag"), "Should contain Lag label: " .. tabline)
        assert(not tabline:find("|"), "Should not contain separator when no stats: " .. tabline)
    end)

    it("shows AI label when usage exists without lag", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("AI"), "Should contain AI label: " .. tabline)
        assert(tabline:find("|"), "Should contain separator with stats: " .. tabline)
    end)

    it("shows Lag label with stats when both active", function()
        lag.start(function() end, function() return { conversation = {} } end)
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("Lag"), "Should show Lag not AI when lag is on: " .. tabline)
        assert(tabline:find("100 in"), "Should contain stats: " .. tabline)
    end)

    it("right-aligns content with %=", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("^%%="), "Should start with %%= for right alignment: " .. tabline)
    end)
end)
