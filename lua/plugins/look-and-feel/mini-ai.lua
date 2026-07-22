return {
    'nvim-mini/mini.ai',
    event = "BufEnter",
    version = false,
    opts = {
        mappings = {
            around_next = 'na',
            inside_next = 'ni',
            around_last = 'pa',
            inside_last = 'pi',
        }
    }
}
