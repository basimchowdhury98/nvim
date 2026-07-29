vim.api.nvim_create_autocmd('FileType', {
    pattern = "markdown",
    once = true,
    callback = function()
        vim.pack.add { "https://github.com/MeanderingProgrammer/render-markdown.nvim" }

        require('render-markdown').setup {
            heading = {
                sign = false,
                icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
                position = 'eol',
                backgrounds = {},
            },
            pipe_table = {
                enabled = false
            }

        }
    end
})
