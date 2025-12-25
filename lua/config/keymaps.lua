-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local map = vim.keymap.set

-- Buffer 切换器
require("config.buffer_switcher").setup()
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

-- macOS Cmd+/ 注释
map("n", "<D-/>", "gcc", { remap = true, desc = "注释/取消注释（当前行）" })
map("v", "<D-/>", "gc", { remap = true, desc = "注释/取消注释（选中区域）" })

-- macOS Cmd+P 搜索文件 (相当于 leader fF)
map("n", "<D-p>", function()
  Snacks.picker.files()
end, { desc = "搜索文件" })

-- macOS Cmd+Shift+F 在 cwd 范围内搜索
map("n", "<D-F>", function()
  LazyVim.pick("live_grep", { root = false })()
end, { desc = "Grep (cwd)" })

-- macOS Cmd+S 保存文件
map("n", "<D-s>", ":w<CR>", { desc = "保存文件" })
