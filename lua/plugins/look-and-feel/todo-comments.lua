return {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    opts = {
        keywords = {
            TODO = { icon = " ", color = "info" }
        },
        merge_keywords = false
    }
}
