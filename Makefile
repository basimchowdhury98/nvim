.PHONY: test lint

lint:
	luacheck init.lua lua/ specs/
	nvim --headless -l scripts/lint_tests.lua

test:
	nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }"
