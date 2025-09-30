local ls = require('luasnip')
local snippet = ls.snippet
local text = ls.text_node
local ins = ls.insert_node

return {
    snippet("propi", {
        text("public "),
        ins(1, "string"),
        text(" "),
        ins(2, "PropertyName"),
        text(" { get; init; }"),
        ins(0)
    })
}
