-- VSCode 风格 Buffer 切换器
-- 使用 Ctrl+Tab 选中下一个，松 Ctrl 后切换

local M = {}

M.win_id = nil
M.buf_id = nil
M.prev_buf = nil -- 追踪上一个访问的 buffer
M.switch_history = {}
M.selection = 1
M.active = false
M.ctrl_release_timer = nil
M.closing = false -- 防止重复关闭

-- 手动切换 buffer 后更新 prev_buf
local bufenter_augroup = vim.api.nvim_create_augroup("BufferSwitcherBufEnter", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  group = bufenter_augroup,
  pattern = "*",
  callback = function()
    -- 只在 switcher 关闭且 prev_buf 无效时才更新（通过 switcher 切换会自己设置 prev_buf）
    if not M.active then
      local current_buf = vim.api.nvim_get_current_buf()
      if not M.prev_buf or not vim.api.nvim_buf_is_valid(M.prev_buf) then
        M.prev_buf = current_buf
      end
    end
  end,
})

function M.close()
  if M.closing then
    return
  end
  M.closing = true
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
  end
  M.win_id = nil
  M.buf_id = nil
  M.active = false
  M.closing = false
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
  -- 排除侧边栏和特殊 buffer
  if filetype == "NvimTree" or filetype == "neo-tree" or filetype == "floaterm" or filetype == "snacks_picker_list" or filetype == "starter" then
    return false
  end
  -- 排除无名称的 buffer（如 start page）
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
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
  local current_buf = vim.api.nvim_get_current_buf()

  -- 保存 prev_buf（close() 后 BufEnter 可能会覆盖它）
  local prev_buf = M.prev_buf

  -- 如果 prev_buf 还没设置，设置为当前 buffer（第一次打开）
  if not prev_buf then
    prev_buf = current_buf
  end

  M.close()

  -- 恢复 prev_buf（close() 后的 BufEnter 可能已经覆盖了）
  M.prev_buf = prev_buf

  -- 收集所有可编辑 buffer（除了当前）
  local other_bufs = vim.tbl_filter(function(b)
    return b ~= current_buf and M.is_editable_buffer(b)
  end, vim.api.nvim_list_bufs())

  -- 检查是否有足够的可切换 buffer
  local switchable_count = #other_bufs + (M.is_editable_buffer(current_buf) and 1 or 0)
  if switchable_count <= 1 then
    return
  end

  -- 排序：上一个 buffer 优先，其余按 buffer 编号从小到大
  table.sort(other_bufs, function(a, b)
    if a == prev_buf then
      return true
    end
    if b == prev_buf then
      return false
    end
    return a < b
  end)

  -- 构建 switch_history：最多 10 个
  M.switch_history = {}
  local current_is_editable = M.is_editable_buffer(current_buf)
  if current_is_editable then
    table.insert(M.switch_history, current_buf)
  end

  -- 添加上一个 buffer
  local has_prev = false
  if prev_buf and prev_buf ~= current_buf and vim.api.nvim_buf_is_valid(prev_buf) and M.is_editable_buffer(prev_buf) then
    table.insert(M.switch_history, prev_buf)
    has_prev = true
  end

  -- 添加其他 buffer，限制最多 10 项
  for _, buf in ipairs(other_bufs) do
    if buf ~= prev_buf and #M.switch_history < 10 then
      table.insert(M.switch_history, buf)
    end
  end

  -- 如果当前 buffer 不可编辑，selection 从 1 开始（上一个），否则从 2 开始
  M.selection = current_is_editable and 2 or 1
  M.active = true

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "buffer-switcher")

  local width = 30
  local height = math.min(#M.switch_history, 10)
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
  -- 如果 selection 为 1（没有上一个），循环到 2
  if M.selection < 2 then
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

  -- 如果选中的是当前 buffer（selection = 1），不切换
  if M.selection == 1 then
    M.close()
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local target_buf = M.switch_history[M.selection]

  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    -- 切换前，设置 prev_buf 为当前 buffer（作为"上一个"供下次使用）
    M.prev_buf = current_buf
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
    end, 400)

    return ""
  end, { expr = true, desc = "选中下一个 (松 Ctrl 切换)" })
end

return M
