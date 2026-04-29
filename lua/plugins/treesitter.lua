return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		init = function()
			local ensureInstalled = {
				"c",
				"lua",
				"vim",
				"vimdoc",
				"markdown",
				"markdown_inline",
				"typescript",
				"javascript",
				"tsx",
				"c_sharp",
				"angular",
				"go",
                "python"
			}
			local alreadyInstalled = require("nvim-treesitter.config").get_installed()
			local parsersToInstall = vim.iter(ensureInstalled)
				:filter(function(parser)
					return not vim.tbl_contains(alreadyInstalled, parser)
				end)
				:totable()
			require("nvim-treesitter").install(parsersToInstall)
			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					pcall(vim.treesitter.start)
					-- Enable treesitter-based indentation
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require("treesitter-context").setup({
				enable = true,
				max_lines = 3, -- How many context lines to show
				min_window_height = 0,
				line_numbers = true,
				multiline_threshold = 2, -- Maximum number of lines to show for a single context
				trim_scope = "outer", -- Which context lines to discard if `max_lines` is exceeded
				mode = "cursor", -- Line used to calculate context. Choices: 'cursor', 'topline'
			})
		end,
	},
}
