.PHONY: test lint val

lint:
	@luacheck init.lua lua/ specs/; luacheck_exit=$$?; \
	nvim --headless -l scripts/lint_tests.lua; nvim_exit=$$?; \
	exit $$(( luacheck_exit || nvim_exit ))

test:
	nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }"

val:
	@start_time=$$(date +%s%N); \
	test_ok=0; luacheck_ok=0; nvimlint_ok=0; \
	echo "========== Running Tests =========="; \
	nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }" && test_ok=1; \
	echo ""; \
	echo "========== Running Luacheck =========="; \
	luacheck init.lua lua/ specs/ && luacheck_ok=1; \
	echo ""; \
	echo "========== Running Lint Tests =========="; \
	nvim --headless -l scripts/lint_tests.lua && nvimlint_ok=1; \
	echo ""; \
	failed=0; \
	if [ "$$test_ok" = "1" ]; then test_sym="\033[32m✓\033[0m"; else test_sym="\033[31m✗\033[0m"; failed=1; fi; \
	if [ "$$luacheck_ok" = "1" ]; then lc_sym="\033[32m✓\033[0m"; else lc_sym="\033[31m✗\033[0m"; failed=1; fi; \
	if [ "$$nvimlint_ok" = "1" ]; then nl_sym="\033[32m✓\033[0m"; else nl_sym="\033[31m✗\033[0m"; failed=1; fi; \
	elapsed_ms=$$(( ($$(date +%s%N) - $$start_time) / 1000000 )); \
	printf "TESTS: $$test_sym  LUACHECK: $$lc_sym  LINT_TESTS: $$nl_sym  [%dms]\n" "$$elapsed_ms"; \
	if [ "$$failed" = "1" ]; then exit 1; fi
