return {
    "mason-org/mason.nvim",
    cmd = {
        "Mason"
    },
    init = function()
        local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
        vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
    end,
    opts = {
        PATH = "skip",
    },
}
