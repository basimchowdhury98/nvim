local map = vim.keymap.set
require("utils.terminal")

map("t", "<C-p>", "<Up>", { desc = "[P]revious terminal command" })
map("t", "<C-n>", "<Down>", { desc = "[N]ext terminal command" })
