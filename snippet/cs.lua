local ls = require('luasnip')
local s = ls.snippet
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local t = ls.text_node
local d = ls.dynamic_node
local sn = ls.sn
local fmt = require('luasnip.extras.fmt').fmt

local field_name = function(index)
    return f(function(arg)
        local input = arg[1][1]
        if input == nil or input == "" then
            return ""
        end

        -- Check if starts with capital I and skip it
        local start_idx = 1
        if input:sub(1, 1) == "I" then
            start_idx = 2
        end

        -- Handle case where string was just "I"
        -- A bit imprecise because it treats any leading 'I' as an interface
        -- Could be bettwe with treesitter
        if start_idx > #input then
            return ""
        end

        -- Build output: lowercase first char, then rest as-is
        local first_char = input:sub(start_idx, start_idx):lower()
        local rest = input:sub(start_idx + 1)

        return first_char .. rest
    end, { index })
end

local function prop(pos)
    return c(pos, {
        fmt("public {} {} {{ get; init; }} = {}{};", { i(1, "string?"), i(2, "PropertyName"), i(3, "default"), i(0) }),
        fmt("public required {} {} {{ get; init; }}{}", { i(1, "string"), i(2, "PropertyName"), i(0) })
    })
end

local function generate_props(_, _, _, more)
    local nodes = {}
    if more then
        table.insert(nodes, t { "", "\t" })
    end
    table.insert(nodes, prop(1))
    table.insert(nodes, t({ "", "" }))
    table.insert(nodes, c(2, {
        t("", { node_ext_opts = { active = { virt_text = { { '<- More?' } } } } }),
        d(nil, generate_props, {}, { user_args = { "more" } })
    } ))

    return sn(nil, nodes)
end

return {
    s("prop", prop(1)),
    s("funfact", fmt("[Fact]\npublic async Task Given{}_When{}_Then{}()\n{{\n\t{}\n}}", { i(1), i(2), i(3), i(0) })),
    s("field", fmt("private readonly {} _{};", { i(1, "type"), field_name(1) })),
    s("debug", fmt('Console.WriteLine($"LOCAL_DEBUG: {}");', { i(1, 'string') })),
    s("record", fmt("public record {}\n{{\n\t{}}}", { i(1, "RecordName"), d(2, generate_props) })),
    s("class", fmt("public class {}\n{{\n\t{}\n}}", { i(1, "ClassName"), i(0) })),
    s("method", fmt("public {} {}({})\n{{\n\t{}\n}}{}", { i(1, "Type"), i(2, "Name"), i(3), i(4), i(0) }))
}
