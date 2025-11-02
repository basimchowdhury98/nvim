local ls = require('luasnip')
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmt = require('luasnip.extras.fmt').fmt

return {
    s("vk", fmt("vim.keymap.set(\"{}\", \"<leader>{}\", {})", { i(1, "n"), i(2), i(0) }))
}
