.PHONY: test lint

lint:
	@luacheck init.lua lua/ specs/; luacheck_exit=$$?; \
	nvim --headless -l scripts/lint_tests.lua; nvim_exit=$$?; \
	exit $$(( luacheck_exit || nvim_exit ))

test:
	nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }"
