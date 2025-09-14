return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
        transparent = true
    },
  },
  { 'nvim-mini/mini.icons', version = false },
  {
      "prichrd/netrw.nvim",
      opts = {},
      config = function()
          require("mini.icons").setup()
          require("netrw").setup({
              use_devicons = true,
              -- other options
          })
      end
  }
}
