return {
    'ggandor/leap.nvim',
    config = function()
        require('leap').opts.safe_labels = {} -- disabled jumping to first match
        vim.api.nvim_set_hl(0, 'LeapBackdrop', { link = 'Comment' }) -- grey out search area
        vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(leap)')
        vim.keymap.set('n', 'S', '<Plug>(leap-from-window)')
    end
}
