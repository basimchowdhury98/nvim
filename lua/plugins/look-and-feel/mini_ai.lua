return {
    'nvim-mini/mini.ai',
    event = "VeryLazy",
    version = false,
    config = function()
        require('mini.ai').setup({
            mappings = {
                around_last = 'ap',
                inside_last = 'ip',
            }
        })
    end
}
