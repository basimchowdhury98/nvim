describe("AI Plugin", function()
	local ai = require("utils.ai")

	it("smoke tests the ai plugin", function()
        ai.stop()
        ai.start()
        ai.stop()

		assert(true, "No errors were thrown")
	end)
end)
