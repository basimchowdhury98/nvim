return {
    'nvim-mini/mini.ai',
    event = "BufEnter",
    version = false,
    opts = {
        mappings = {
            around_next = 'an',
            inside_next = 'in',
            around_last = 'ap',
            inside_last = 'ip',
        }
    }
}
