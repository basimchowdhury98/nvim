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

-- In c# changes all !bool to not bool so its more visible
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cs",
  callback = function()
    local ns = vim.api.nvim_create_namespace('not_operator')

    local function update_conceals()
      vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

      local ok, parser = pcall(vim.treesitter.get_parser, 0, 'c_sharp')
      if not ok or not parser then return end

      local tree = parser:parse()[1]
      if not tree then return end
      local root = tree:root()

      local query = vim.treesitter.query.parse('c_sharp', [[
        (prefix_unary_expression) @negation
      ]])

      for _, node in query:iter_captures(root, 0) do
        local row, col, _, end_col = node:range()
        local text = vim.treesitter.get_node_text(node, 0)

        if text:match('^!') then
          -- Use a single extmark: conceal the '!' and place 'not ' as inline virtual text
          vim.api.nvim_buf_set_extmark(0, ns, row, col, {
            end_col = col + 1,
            conceal = '',
            virt_text = { { 'not ', 'Operator' } },
            virt_text_pos = 'inline',
          })
        end
      end
    end

    -- Set conceallevel so the conceal extmark actually hides the '!'
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = ''

    update_conceals()
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      buffer = 0,
      callback = update_conceals,
    })
  end,
})
