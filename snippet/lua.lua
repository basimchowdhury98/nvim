local ls = require('luasnip')
local s = ls.snippet
local i = ls.insert_node
local fmt = require('luasnip.extras.fmt').fmt
local f = ls.function_node

return
    {
        s("vk", fmt("vim.keymap.set(\"{}\", \"<leader>{}\", {}, {{ desc = \"{}\" }})", { i(1, "n"), i(2), i(3), i(0) })),
        s("debug", fmt('print("LOCAL_DEBUG: {}" .. {});', { i(1), i(0) })),
    },
    {
        s("locr", fmt("local {} = require('{}')",
            {
                f(function(import_name)
                    local parts = vim.split(import_name[1][1], ".", { plain = true })
                    return parts[#parts] or ""
                end, { 1 }),
                i(1)
            }))
    }
