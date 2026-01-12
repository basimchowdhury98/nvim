return {
	"lukas-reineke/indent-blankline.nvim",
	main = "ibl",
	---@module "ibl"
	---@type ibl.config
	opts = {
		scope = {
			enabled = true,
			show_start = false, -- no underline at scope start
			show_end = false, -- no underline at scope end
            include = {
                node_type = {
                    ["*"] = { "class_body", "object" }, -- add to all filetypes
                },
            },
		},
	},
}
