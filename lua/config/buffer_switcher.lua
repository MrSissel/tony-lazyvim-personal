-- VSCode 风格 Buffer 切换器
-- 使用 Ctrl+Tab 选中下一个，松 Ctrl 后切换

local M = {}

M.win_id = nil
M.buf_id = nil
M.switch_history = {}
M.selection = 1
M.active = false
M.ctrl_release_timer = nil

function M.close()
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
  end
  M.win_id = nil
  M.buf_id = nil
  M.active = false
end

function M.render()
  if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
    return
  end

  local lines = {}
  local current_buf = vim.api.nvim_get_current_buf()

  for i, bufnr in ipairs(M.switch_history) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      name = name == "" and "[无名称]" or vim.fs.basename(name)
      local prefix = i == M.selection and "› " or "  "
      local suffix = bufnr == current_buf and " ◀" or ""
      table.insert(lines, prefix .. name .. suffix)
    end
  end

  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.buf_id, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", false)

  -- 高亮当前选中行
  vim.api.nvim_buf_clear_namespace(M.buf_id, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("buffer_switcher")
  vim.api.nvim_buf_add_highlight(M.buf_id, ns, "CursorLine", M.selection - 1, 0, -1)
end

function M.is_editable_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  if filetype == "NvimTree" or filetype == "neo-tree" or filetype == "floaterm" then
    return false
  end
  return true
end

function M.open()
  vim.schedule(function()
    M._open_sync()
  end)
end

function M._open_sync()
  M.close()

  -- 收集所有可编辑 buffer
  local bufs = vim.tbl_filter(function(b)
    return M.is_editable_buffer(b)
  end, vim.api.nvim_list_bufs())

  if #bufs <= 1 then
    return
  end

  -- 按最近使用时间排序（当前 buffer 在最前）
  table.sort(bufs, function(a, b)
    if a == vim.api.nvim_get_current_buf() then
      return true
    end
    if b == vim.api.nvim_get_current_buf() then
      return false
    end
    return a < b
  end)

  M.switch_history = bufs
  M.selection = 2 -- 默认选中上一个
  M.active = true

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "buffer-switcher")

  local width = 30
  local height = math.min(#M.switch_history, 8)
  local row = 1
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  M.win_id = vim.api.nvim_open_win(M.buf_id, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 100,
  })

  vim.api.nvim_win_set_option(M.win_id, "cursorline", true)
  M.render()
end

function M.select_next()
  if not M.active then
    M.open()
    return
  end

  M.selection = M.selection + 1
  if M.selection > #M.switch_history then
    M.selection = 2
  end
  -- 延迟渲染，避免在 buffer 切换时操作
  vim.schedule(function()
    if M.active and M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
      M.render()
    end
  end)
end

function M.confirm_switch()
  if not M.active or not M.selection then
    return
  end

  local target_buf = M.switch_history[M.selection]
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_set_current_buf(target_buf)
  end
  M.close()
end

function M.setup()
  -- 按住 Ctrl + Tab 选中下一个，松 Ctrl 后切换
  vim.keymap.set({ "n", "i" }, "<C-Tab>", function()
    M.select_next()

    -- 重置 timer，400ms 后检测 Ctrl 是否松开
    if M.ctrl_release_timer then
      M.ctrl_release_timer:close()
    end
    M.ctrl_release_timer = vim.defer_fn(function()
      M.confirm_switch()
      M.ctrl_release_timer = nil
    end, 300)

    return ""
  end, { expr = true, desc = "选中下一个 (松 Ctrl 切换)" })
end

return M
