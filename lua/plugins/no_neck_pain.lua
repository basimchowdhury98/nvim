return {
    "shortcuts/no-neck-pain.nvim",
    enabled = false,
    config = function()
        require("no-neck-pain").setup({
            width = 160,
            autocmds = {
                enableOnVimEnter = true
            }
        })
    end
}
