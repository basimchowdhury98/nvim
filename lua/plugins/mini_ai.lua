return {
    'nvim-mini/mini.ai',
    event = "VeryLazy",
    version = false,
    config = function()
      require('mini.ai').setup()
    end
}
