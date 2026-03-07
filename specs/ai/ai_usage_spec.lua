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

describe("AI Usage Last Request", function()
    before_each(function()
        usage.reset()
        lag.reset()
    end)

    it("last_request is nil initially", function()
        local lr = usage._get_last_request()

        eq(nil, lr, "Should be nil before any add")
    end)

    it("last_request reflects the most recent call", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 200, cache_write = 10 } })
        usage.add({ tokens = { input = 500, output = 25, cache_read = 0, cache_write = 0 } })

        local lr = usage._get_last_request()

        eq(500, lr.input, "Should reflect second call's input")
        eq(25, lr.output, "Should reflect second call's output")
        eq(0, lr.cache_read, "Should reflect second call's cache_read")
    end)

    it("last_request is nil after reset", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })
        usage.reset()

        local lr = usage._get_last_request()

        eq(nil, lr, "Should be nil after reset")
    end)

    it("last_request is not set when metadata has no tokens", function()
        usage.add({ cost = 0.01 })

        local lr = usage._get_last_request()

        eq(nil, lr, "Should remain nil without tokens")
    end)
end)

describe("AI Usage Cache History", function()
    before_each(function()
        usage.reset()
        lag.reset()
    end)

    it("cache_history is empty initially", function()
        local ch = usage._get_cache_history()

        eq({}, ch, "Should be empty before any add")
    end)

    it("cache_history records percentage when cache_read > 0", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 900, cache_write = 0 } })

        local ch = usage._get_cache_history()

        eq(1, #ch, "Should have one entry")
        eq(90, ch[1], "Cache rate should be 90% (900/1000)")
    end)

    it("cache_history skips entries with zero cache_read", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local ch = usage._get_cache_history()

        eq({}, ch, "Should be empty when no cache")
    end)

    it("cache_history accumulates up to 3 entries", function()
        usage.add({ tokens = { input = 100, output = 10, cache_read = 900, cache_write = 0 } })
        usage.add({ tokens = { input = 200, output = 10, cache_read = 800, cache_write = 0 } })
        usage.add({ tokens = { input = 300, output = 10, cache_read = 700, cache_write = 0 } })

        local ch = usage._get_cache_history()

        eq(3, #ch, "Should have 3 entries")
        eq(90, ch[1], "First entry: 900/1000")
        eq(80, ch[2], "Second entry: 800/1000")
        eq(70, ch[3], "Third entry: 700/1000")
    end)

    it("cache_history trims oldest when exceeding 3", function()
        usage.add({ tokens = { input = 100, output = 10, cache_read = 900, cache_write = 0 } })
        usage.add({ tokens = { input = 200, output = 10, cache_read = 800, cache_write = 0 } })
        usage.add({ tokens = { input = 300, output = 10, cache_read = 700, cache_write = 0 } })
        usage.add({ tokens = { input = 400, output = 10, cache_read = 600, cache_write = 0 } })

        local ch = usage._get_cache_history()

        eq(3, #ch, "Should cap at 3 entries")
        eq(80, ch[1], "Oldest should be second request: 800/1000")
        eq(70, ch[2], "Middle should be third request: 700/1000")
        eq(60, ch[3], "Latest should be fourth request: 600/1000")
    end)

    it("cache_history is empty after reset", function()
        usage.add({ tokens = { input = 100, output = 10, cache_read = 900, cache_write = 0 } })
        usage.reset()

        local ch = usage._get_cache_history()

        eq({}, ch, "Should be empty after reset")
    end)

    it("cache_history only counts requests with cache data", function()
        usage.add({ tokens = { input = 100, output = 10, cache_read = 900, cache_write = 0 } })
        usage.add({ tokens = { input = 200, output = 10, cache_read = 0, cache_write = 0 } })
        usage.add({ tokens = { input = 300, output = 10, cache_read = 700, cache_write = 0 } })

        local ch = usage._get_cache_history()

        eq(2, #ch, "Should only have 2 entries (skip zero-cache request)")
        eq(90, ch[1], "First cached request")
        eq(70, ch[2], "Second cached request")
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

    it("format_stats shows last request context size", function()
        usage.add({ tokens = { input = 1200, output = 300, cache_read = 0, cache_write = 0 } })

        local stats = usage.format_stats()

        eq("1.2K/? ctx", stats, "Should show last request input as context size")
    end)

    it("format_stats shows total input including cache", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 5000, cache_write = 200 } })

        local stats = usage.format_stats()

        eq("5.3K/? ctx", stats, "Should show total input (uncached + cache read + cache write)")
    end)

    it("format_stats reflects last request only", function()
        usage.add({ tokens = { input = 10000, output = 500, cache_read = 0, cache_write = 0 } })
        usage.add({ tokens = { input = 200, output = 50, cache_read = 0, cache_write = 0 } })

        local stats = usage.format_stats()

        eq("200/? ctx", stats, "Should show last request, not cumulative")
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

    it("shows strikethrough Lag label when usage exists without lag", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("AILagOff"), "Should use strikethrough highlight: " .. tabline)
        assert(tabline:find("Lag"), "Should still say Lag: " .. tabline)
    end)

    it("shows Lag label with context size when both active", function()
        lag.start(function() end, function() return { conversation = {} } end)
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("Lag"), "Should show Lag when lag is on: " .. tabline)
        assert(tabline:find("100/%? ctx"), "Should contain context size: " .. tabline)
    end)

    it("right-aligns content with %=", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("^%%="), "Should start with %%= for right alignment: " .. tabline)
    end)

    it("includes cache history with dim highlights for older entries", function()
        usage.add({ tokens = { input = 100, output = 10, cache_read = 900, cache_write = 0 } })
        usage.add({ tokens = { input = 200, output = 10, cache_read = 800, cache_write = 0 } })
        usage.add({ tokens = { input = 300, output = 10, cache_read = 700, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(tabline:find("AILagDim"), "Should use dim highlight for older entries: " .. tabline)
        assert(tabline:find("70%%%%"), "Should contain latest cache rate: " .. tabline)
    end)

    it("omits cache section when no cache history", function()
        usage.add({ tokens = { input = 100, output = 50, cache_read = 0, cache_write = 0 } })

        local tabline = usage.build_tabline()

        assert(not tabline:find("AILagDim"), "Should not contain cache history section: " .. tabline)
    end)
end)
