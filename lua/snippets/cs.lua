local ls = require('luasnip')
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
    s("propi", {
        t("public "),
        i(1, "string"),
        t(" "),
        i(2, "PropertyName"),
        t(" { get; init; }"),
        i(0)
    }),
   s("funfact", {
       t("public async Task Given"),
       i(1),
       t("_When"),
       i(2),
       t("_Then"),
       i(3),
       t({ "()", "{", "\t" }),
       i(4),
       t({ "", "}" }),
       i(0)
   })
}
