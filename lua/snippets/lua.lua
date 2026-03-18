local ls = require('luasnip')
local s = ls.snippet
local i = ls.insert_node
local fmt = require('luasnip.extras.fmt').fmt

return {
    s("vk", fmt("vim.keymap.set(\"{}\", \"<leader>{}\", {}, {{ desc = \"{}\" }})", { i(1, "n"), i(2), i(3), i(0) }))
}
