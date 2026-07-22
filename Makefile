.PHONY: test lint val

FAILED_TEST_OUTPUT = awk '/^(\033\[[0-9;]*m)?(Fail|Error)(\033\[[0-9;]*m)?[[:space:]]*\|\|/ { printing = 1; print; next } /^(\033\[[0-9;]*m)?(Success|Fail|Error)(\033\[[0-9;]*m)?[[:space:]]*\|\|/ { printing = 0; next } printing { print }'

lint:
	@luacheck .; luacheck_exit=$$?; \
	nvim --headless -l scripts/lint_tests.lua; nvim_exit=$$?; \
	exit $$(( luacheck_exit || nvim_exit ))

test:
	@tmp=$$(mktemp); \
	nvim --headless -u ./lua/specs/init.lua -c "PlenaryBustedDirectory lua/specs/ { minimal_init = 'lua/specs/init.lua' }" > "$$tmp" 2>&1; \
	status=$$?; \
	cat "$$tmp"; \
	if [ "$$status" != "0" ]; then \
		echo ""; \
		echo "========== Failed Test Output =========="; \
		$(FAILED_TEST_OUTPUT) "$$tmp"; \
	fi; \
	rm -f "$$tmp"; \
	exit "$$status"

val:
	@start_time=$$(date +%s%N); \
	test_ok=0; luacheck_ok=0; nvimlint_ok=0; \
	test_output=$$(mktemp); \
	echo "========== Running Tests =========="; \
	nvim --headless -u ./lua/specs/init.lua -c "PlenaryBustedDirectory lua/specs/ { minimal_init = 'lua/specs/init.lua' }" > "$$test_output" 2>&1; \
	test_status=$$?; \
	cat "$$test_output"; \
	if [ "$$test_status" = "0" ]; then test_ok=1; fi; \
	echo ""; \
	echo "========== Running Luacheck =========="; \
	luacheck . && luacheck_ok=1; \
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
	if [ "$$test_ok" != "1" ]; then \
		echo ""; \
		echo "========== Failed Test Output =========="; \
		$(FAILED_TEST_OUTPUT) "$$test_output"; \
	fi; \
	rm -f "$$test_output"; \
	if [ "$$failed" = "1" ]; then exit 1; fi
