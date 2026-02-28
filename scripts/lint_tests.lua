local function find_lua_files(dir)
    local files = {}
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return files end

    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end

        local full_path = dir .. "/" .. name
        if ftype == "directory" and name ~= ".git" and name ~= ".github" then
            for _, f in ipairs(find_lua_files(full_path)) do
                files[#files + 1] = f
            end
        elseif ftype == "file" and name:match("%.lua$") then
            files[#files + 1] = full_path
        end
    end
    return files
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function is_blank(line)
    return line:match("^%s*$") ~= nil
end

local function is_section_label_comment(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    if not trimmed then return false end
    local comment = trimmed:match("^%-%-(.*)$")
    if not comment then return false end
    comment = comment:match("^%s*(.-)%s*$"):lower()
    return comment == "arrange" or comment == "act" or comment == "assert"
end

local function count_sections(lines)
    local sections = 0
    local in_section = false

    for _, line in ipairs(lines) do
        if is_blank(line) then
            in_section = false
        else
            if not in_section then
                sections = sections + 1
                in_section = true
            end
        end
    end

    return sections
end

local function get_lines_from_range(source_lines, start_row, end_row)
    local result = {}
    for i = start_row, end_row do
        result[#result + 1] = source_lines[i]
    end
    return result
end

local function strip_surrounding_blanks(lines)
    while #lines > 0 and is_blank(lines[1]) do
        table.remove(lines, 1)
    end
    while #lines > 0 and is_blank(lines[#lines]) do
        table.remove(lines, #lines)
    end
    return lines
end

--- Find all it() calls in a parsed tree and return their body ranges
--- Each it() is: function_call where the callee identifier is "it",
--- with a function_definition argument whose block is the test body.
local function find_it_blocks(root, source)
    local query = vim.treesitter.query.parse("lua", [[
        (function_call
            name: (identifier) @fn_name
            arguments: (arguments
                (function_definition
                    body: (block) @body))
            (#eq? @fn_name "it"))
    ]])

    local results = {}
    for _, match in query:iter_matches(root, source, 0, -1, { all = true }) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            if name == "body" then
                local node = nodes[1]
                local start_row, _, end_row, _ = node:range()
                results[#results + 1] = {
                    -- treesitter rows are 0-indexed, convert to 1-indexed
                    body_start = start_row + 1,
                    body_end = end_row + 1,
                    -- the it() call itself is the parent function_call
                    it_line = node:parent():parent():parent():start() + 1,
                }
            end
        end
    end
    return results
end

--- Count the arguments in a function_call's arguments node.
--- Returns the number of expression children (skips punctuation like commas/parens).
local function count_call_args(args_node)
    local count = 0
    for child in args_node:iter_children() do
        local t = child:type()
        if t ~= "(" and t ~= ")" and t ~= "," then
            count = count + 1
        end
    end
    return count
end

--- Find assertions missing failure messages in a spec file.
--- Checks: eq(a, b) missing 3rd arg, assert(expr) missing 2nd arg.
local function check_assertion_messages(root, source, path, errors)
    local query = vim.treesitter.query.parse("lua", [[
        (function_call
            name: (identifier) @fn_name
            arguments: (arguments) @args
            (#any-of? @fn_name "eq" "assert"))
    ]])

    for _, match in query:iter_matches(root, source, 0, -1, { all = true }) do
        local fn_name_node = nil
        local args_node = nil
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            if name == "fn_name" then fn_name_node = nodes[1] end
            if name == "args" then args_node = nodes[1] end
        end

        if fn_name_node and args_node then
            local fn_name = vim.treesitter.get_node_text(fn_name_node, source)
            local arg_count = count_call_args(args_node)
            local line = fn_name_node:start() + 1 -- 0-indexed to 1-indexed

            if fn_name == "eq" and arg_count < 3 then
                errors[#errors + 1] = {
                    file = path,
                    line = line,
                    msg = "eq() missing failure message (expected 3rd string argument)",
                }
            elseif fn_name == "assert" and arg_count < 2 then
                errors[#errors + 1] = {
                    file = path,
                    line = line,
                    msg = "assert() missing failure message (expected 2nd string argument)",
                }
            end
        end
    end
end

local function check_file(path, errors, is_spec)
    local source = read_file(path)
    if not source then return end

    local source_lines = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        source_lines[#source_lines + 1] = line
    end

    local parser = vim.treesitter.get_string_parser(source, "lua")
    local tree = parser:parse()[1]
    if not tree then return end

    local root = tree:root()
    local it_blocks = find_it_blocks(root, source)

    for _, block in ipairs(it_blocks) do
        local body_lines = get_lines_from_range(source_lines, block.body_start, block.body_end)
        body_lines = strip_surrounding_blanks(body_lines)

        local sections = count_sections(body_lines)

        if sections < 2 then
            errors[#errors + 1] = {
                file = path,
                line = block.it_line,
                msg = string.format(
                    "test body has %d section(s), expected 2 or 3 (separate arrange/act/assert with blank lines)",
                    sections
                ),
            }
        elseif sections > 3 then
            errors[#errors + 1] = {
                file = path,
                line = block.it_line,
                msg = string.format(
                    "test body has %d sections, expected 2 or 3 (too fragmented)",
                    sections
                ),
            }
        end

        -- Check for section-labeling comments
        for i = block.body_start, block.body_end do
            if is_section_label_comment(source_lines[i]) then
                errors[#errors + 1] = {
                    file = path,
                    line = i,
                    msg = "section-labeling comment found (use blank lines instead of '-- arrange/act/assert')",
                }
            end
        end
    end

    if is_spec then
        check_assertion_messages(root, source, path, errors)
    end
end

local function main()
    local root = vim.fn.getcwd()
    local all_dirs = { root .. "/lua", root .. "/specs" }
    local spec_dirs = { root .. "/specs" }
    local single_files = { root .. "/init.lua" }

    local lua_files = {}
    for _, dir in ipairs(all_dirs) do
        for _, f in ipairs(find_lua_files(dir)) do
            lua_files[#lua_files + 1] = f
        end
    end
    for _, f in ipairs(single_files) do
        lua_files[#lua_files + 1] = f
    end

    local spec_files = {}
    for _, dir in ipairs(spec_dirs) do
        for _, f in ipairs(find_lua_files(dir)) do
            spec_files[f] = true
        end
    end

    local errors = {}

    for _, path in ipairs(lua_files) do
        check_file(path, errors, spec_files[path])
    end

    if #errors == 0 then
        print("lint_tests: all tests pass convention checks")
        vim.cmd("cquit 0")
        return
    end

    for _, err in ipairs(errors) do
        local rel_path = err.file:gsub("^" .. root .. "/", "")
        io.stderr:write(string.format("%s:%d: %s\n", rel_path, err.line, err.msg))
    end

    io.stderr:write(string.format("\nlint_tests: %d violation(s) found\n", #errors))
    io.stderr:write("Rules:\n")
    io.stderr:write("  - every it() body must have 2 or 3 sections separated by 1 blank line (no section-labeling comments)\n")
    io.stderr:write("  - every eq() must have a 3rd failure message argument\n")
    io.stderr:write("  - every assert() must have a 2nd failure message argument\n")
    vim.cmd("cquit 1")
end

main()
