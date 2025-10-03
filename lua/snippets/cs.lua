local ls = require('luasnip')
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmt = require('luasnip.extras.fmt').fmt

return {
    s("propi", {
        t("public "),
        i(1, "string"),
        t(" "),
        i(2, "PropertyName"),
        t(" { get; init; }"),
        i(0)
    }),
    s("funfact", fmt("[Fact]\npublic async Task GivenNew{}_When{}_Then{}()\n{{\n\t{}\n}}", { i(1), i(2), i(3), i(0) })),
    s("rof", {
        t("private readonly "),
        i(1, "type"),
        t(" _"),
        i(2, "fieldName"),
        t(";"),
        i(0)
    })
}
