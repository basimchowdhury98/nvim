return {
    "nvim-treesitter/nvim-treesitter", 
    branch = 'master', 
    lazy = false, 
    build = ":TSUpdate",
    opts = {
	  -- A list of parser names, or "all" (the listed parsers MUST always be installed)
	  ensure_installed = { "c", "lua", "vim", "vimdoc", "markdown", "markdown_inline", "typescript", "javascript", "tsx", "jsx", "c_sharp"},

	  -- Install parsers synchronously (only applied to `ensure_installed`)
	  sync_install = false,

	  -- Automatically install missing parsers when entering buffer
	  -- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
	  auto_install = true,

	  highlight = {
	    enable = true,

	    additional_vim_regex_highlighting = false,
	  },
	}
}
