-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set
-- 窗口调整
map("n", "<A-Up>", ":resize +2<CR>", { desc = "增加高度" })
map("n", "<A-Down>", ":resize -2<CR>", { desc = "减少高度" })
map("n", "<A-Left>", ":vertical resize -2<CR>", { desc = "减少宽度" })
map("n", "<A-Right>", ":vertical resize +2<CR>", { desc = "增加宽度" })

-- Normal J/K
map("n", "J", "5j", { desc = "向下5行" })
map("n", "K", "5k", { desc = "向上5行" })
map("n", "gh", vim.lsp.buf.hover, { desc = "显示光标处的悬停信息" })
-- L 移动到行末（当前行最后一个非空字符）
map("n", "L", "g_", { desc = "移动到行末（最后一个非空字符）" })
-- H 移动到行首（当前行第一个非空字符）
map("n", "H", "^", { desc = "移动到行首（第一个非空字符）" })
