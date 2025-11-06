.PHONY: test

test:
	nvim % nvim --headless -u ./specs/init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = 'specs/init.lua' }"
