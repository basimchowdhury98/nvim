return {
    capabilities = {
        workspace = {
            didChangeWatchedFiles = { dynamicRegistration = false },
        },
    },
    cmd = {
        vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "roslyn-language-server"),
        "--stdio",
    },
    cmd_env = {
        DOTNET_ROOT = vim.env.DOTNET_ROOT or vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
        DOTNET_ROOT_ARM64 = vim.env.DOTNET_ROOT_ARM64 or vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
        DOTNET_gcServer = "0",
        DOTNET_GCConserveMemory = "9",
        DOTNET_GCHeapHardLimit = "0x140000000",
    },
    settings = {
        ["csharp|background_analysis"] = {
            dotnet_analyzer_diagnostics_scope = "openFiles",
            dotnet_compiler_diagnostics_scope = "openFiles",
        },
    },
}
