.PHONY: test lint e2e

lint:
	@luacheck init.lua lua/ specs/ e2e/specs/; luacheck_exit=$$?; \
	nvim --headless -l scripts/lint_tests.lua; nvim_exit=$$?; \
	exit $$(( luacheck_exit || nvim_exit ))

test:
	nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }"

e2e:
	bash e2e/run.sh
