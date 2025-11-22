vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "help",
  callback = function()
    vim.cmd("wincmd L")
  end,
})

-- Automatically resize split when window is resized
vim.api.nvim_create_autocmd('VimResized', {
  pattern = '*',
  command = 'wincmd ='
})
