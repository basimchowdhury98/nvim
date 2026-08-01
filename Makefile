.PHONY: test lint val

FAILED_TEST_OUTPUT = awk '/^(\033\[[0-9;]*m)?(Fail|Error)(\033\[[0-9;]*m)?[[:space:]]*\|\|/ { printing = 1; print; next } /^(\033\[[0-9;]*m)?(Success|Fail|Error)(\033\[[0-9;]*m)?[[:space:]]*\|\|/ { printing = 0; next } printing { print }'

lint:
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	VIMRUNTIME="$$(nvim --clean --headless --noplugin -i NONE +'lua io.write(vim.env.VIMRUNTIME)' +qa)" \
		lua-language-server \
		--check=. \
		--checklevel=Hint \
		--check_format=pretty \
		--configpath=.luarc.json \
		--logpath="$$tmp/log" \
		--metapath="$$tmp/meta"

test:
	@tmp=$$(mktemp); \
	nvim --headless -u ./lua/_spec-init.lua -c "PlenaryBustedDirectory lua/ { minimal_init = 'lua/_spec-init.lua' }" > "$$tmp" 2>&1; \
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
	test_ok=0; luals_ok=0; \
	test_output=$$(mktemp); \
	echo "========== Running Tests =========="; \
	nvim --headless -u ./lua/_spec-init.lua -c "PlenaryBustedDirectory lua/ { minimal_init = 'lua/_spec-init.lua' }" > "$$test_output" 2>&1; \
	test_status=$$?; \
	cat "$$test_output"; \
	if [ "$$test_status" = "0" ]; then test_ok=1; fi; \
	echo ""; \
	echo "========== Running LuaLS =========="; \
	$(MAKE) --no-print-directory lint && luals_ok=1; \
	echo ""; \
	failed=0; \
	if [ "$$test_ok" = "1" ]; then test_sym="\033[32m✓\033[0m"; else test_sym="\033[31m✗\033[0m"; failed=1; fi; \
	if [ "$$luals_ok" = "1" ]; then luals_sym="\033[32m✓\033[0m"; else luals_sym="\033[31m✗\033[0m"; failed=1; fi; \
	elapsed_ms=$$(( ($$(date +%s%N) - $$start_time) / 1000000 )); \
	printf "TESTS: $$test_sym  LUALS: $$luals_sym  [%dms]\n" "$$elapsed_ms"; \
	if [ "$$test_ok" != "1" ]; then \
		echo ""; \
		echo "========== Failed Test Output =========="; \
		$(FAILED_TEST_OUTPUT) "$$test_output"; \
	fi; \
	rm -f "$$test_output"; \
	if [ "$$failed" = "1" ]; then exit 1; fi
