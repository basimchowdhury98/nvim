local ls = require('luasnip')
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require('luasnip.extras.fmt').fmt

local fieldName = function(index)
    return f(function(arg)
        local input = arg[1][1]
        if input == nil then
            return ""
        end
        if input == "" then
            return ""
        end

        -- Check if starts with capital I and skip it
        local start_idx = 1
        if input:sub(1, 1) == "I" then
            start_idx = 2
        end

        -- Handle case where string was just "I"
        if start_idx > #input then
            return ""
        end

        -- Build output: lowercase first char, then rest as-is
        local first_char = input:sub(start_idx, start_idx):lower()
        local rest = input:sub(start_idx + 1)

        return first_char .. rest
    end, { index })
end

return {
    s("propi", fmt("public {} {} {{ get; init; }}{}", { i(1, "string"), i(2, "PropertyName"), i(0) })),
    s("propir", fmt("public required {} {} {{ get; init; }}{}", { i(1, "string"), i(2, "PropertyName"), i(0) })),
    s("funfact", fmt("[Fact]\npublic async Task Given{}_When{}_Then{}()\n{{\n\t{}\n}}", { i(1), i(2), i(3), i(0) })),
    s("dif", fmt("private readonly {} _{};", { i(1, "type"), fieldName(1) }))
}
