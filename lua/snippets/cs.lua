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
       t({ "[Fact]", "public async Task Given" }),
       i(1),
       t("_When"),
       i(2),
       t("_Then"),
       i(3),
       t({ "()", "{", "\t" }),
       i(0),
       t({ "", "}" }),
   }),
   s("rof", {
       t("private readonly "),
       i(1, "type"),
       t(" _"),
       i(2, "fieldName"),
       t(";"),
       i(0)
   })
}
