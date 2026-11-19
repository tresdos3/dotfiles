-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Tabs: Alt + left/right
vim.keymap.set("n", "<A-h>", "<cmd>tabprevious<cr>", { desc = "Prev Tab" })
vim.keymap.set("n", "<A-l>", "<cmd>tabnext<cr>", { desc = "Next Tab" })

-- Insert mode cursor navigation
vim.keymap.set("i", "<M-h>", "<Left>", { desc = "Move left" })
vim.keymap.set("i", "<M-j>", "<Down>", { desc = "Move down" })
vim.keymap.set("i", "<M-k>", "<Up>", { desc = "Move up" })
vim.keymap.set("i", "<M-l>", "<Right>", { desc = "Move right" })
