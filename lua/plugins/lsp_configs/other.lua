return {
    lua_ls = {},
    bashls = {
        settings = {
            bashIde = {
                shellcheckPath = vim.fn.stdpath("data") .. "/mason/bin/shellcheck",
            },
        },
    },
    basedpyright = {
        settings = {
            basedpyright = {
                analysis = {
                    diagnosticMode = "workspace",
                },
            },
        },
    },
    angularls = {},
    ts_ls = {},
    clangd = {
        cmd = {
            "clangd",
            "--fallback-style=webkit",
        },
        filetypes = { "c", "cpp" },
    },
    shellcheck = {},
}
