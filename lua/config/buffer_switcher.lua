-- VSCode 风格 Buffer 切换器
-- 使用 Ctrl+Tab 选中下一个，松 Ctrl 后切换

local M = {}

M.win_id = nil
M.buf_id = nil
M.prev_buf = nil -- 追踪上一个访问的 buffer
M.buf_access_time = {} -- 追踪每个 buffer 的最后访问时间 {bufnr = timestamp}
M.switch_history = {} -- 存储 {bufnr, path} 元组
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
    -- 只记录 buffer 访问时间，prev_buf 只在 switcher 切换时更新
    local bufnr = vim.api.nvim_get_current_buf()
    M.buf_access_time[bufnr] = vim.loop.now()
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
  local width = vim.api.nvim_win_get_width(M.win_id)

  -- 获取当前 buffer 的项目根目录
  local root_dir = vim.fs.root(current_buf, { '.git', 'package.json', 'pyproject.toml', '.gitignore' }) or ""

  -- 清除旧高亮
  vim.api.nvim_buf_clear_namespace(M.buf_id, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace("buffer_switcher")

  for i, entry in ipairs(M.switch_history) do
    local bufnr, path = entry.bufnr, entry.path
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.fs.basename(path)
      local display_path
      if path == "" then
        display_path = "[无名称]"
      elseif root_dir ~= "" and path:find(root_dir, 1, true) == 1 then
        -- 转换为相对于项目根目录的路径，只显示目录
        local relative = path:sub(#root_dir + 2)
        display_path = vim.fs.dirname(relative)
      else
        -- 如果不在项目根目录下，显示完整目录路径
        display_path = vim.fs.dirname(path)
      end
      local prefix = i == M.selection and "› " or "  "
      local suffix = bufnr == current_buf and " ◀" or ""

      -- 左侧文件名，右侧路径，中间空格填充对齐
      local left = prefix .. name .. suffix
      local right = display_path
      local padding = width - #left - #right - 2
      if padding < 1 then
        padding = 1
      end
      local line = left .. string.rep(" ", padding) .. right
      table.insert(lines, { line = line, bufnr = bufnr, name = name, prefix = prefix, suffix = suffix, display_path = display_path })
    end
  end

  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.buf_id, 0, -1, false, vim.tbl_map(function(x) return x.line end, lines))
  vim.api.nvim_buf_set_option(M.buf_id, "modifiable", false)

  -- 高亮（必须在 set_lines 之后执行）
  for i, item in ipairs(lines) do
    local prefix_len = #item.prefix
    local name_len = #item.name
    local suffix_len = #item.suffix
    local right_start = width - #item.display_path - 2
    local is_selected = (i == M.selection)

    if is_selected then
      vim.api.nvim_buf_add_highlight(M.buf_id, ns, "CursorLine", i - 1, 0, -1)
    end
    -- 文件名用深色
    vim.api.nvim_buf_add_highlight(M.buf_id, ns, "BufferSwitcherName", i - 1, prefix_len, prefix_len + name_len + suffix_len)
    -- 路径用灰色（确保 column 在有效范围内）
    if right_start >= 0 then
      -- 暂时统一用 BufferSwitcherName，路径和文件名同色
      vim.api.nvim_buf_add_highlight(M.buf_id, ns, "BufferSwitcherName", i - 1, right_start, -1)
    end
  end
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
  local current_path = vim.api.nvim_buf_get_name(current_buf)

  M.close()

  -- switcher 打开时，当前文件永远是 prev_buf（排在第一位）
  M.prev_buf = current_buf

  -- 收集所有可编辑 buffer，存储为 {bufnr, path} 格式
  local other_bufs = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= current_buf and M.is_editable_buffer(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      table.insert(other_bufs, { bufnr = bufnr, path = path })
    end
  end

  -- 检查是否有足够的可切换 buffer
  local switchable_count = #other_bufs + (M.is_editable_buffer(current_buf) and 1 or 0)
  if switchable_count <= 1 then
    return
  end

  -- 排序：上一个 buffer 优先，其余按访问时间从新到旧（MRU）
  local prev_path = vim.api.nvim_buf_is_valid(M.prev_buf) and vim.api.nvim_buf_get_name(M.prev_buf) or ""
  table.sort(other_bufs, function(a, b)
    if M.prev_buf and a.bufnr == M.prev_buf then
      return true
    end
    if M.prev_buf and b.bufnr == M.prev_buf then
      return false
    end
    -- 按访问时间降序（时间戳大的在前面）
    local time_a = M.buf_access_time[a.bufnr] or 0
    local time_b = M.buf_access_time[b.bufnr] or 0
    if time_a ~= time_b then
      return time_a > time_b
    end
    -- 访问时间相同则按 buffer 编号
    return a.bufnr < b.bufnr
  end)

  -- 构建 switch_history：最多 10 个
  M.switch_history = {}
  local current_is_editable = M.is_editable_buffer(current_buf)
  if current_is_editable then
    table.insert(M.switch_history, { bufnr = current_buf, path = current_path })
  end

  -- 添加上一个 buffer
  if M.prev_buf and M.prev_buf ~= current_buf and vim.api.nvim_buf_is_valid(M.prev_buf) and M.is_editable_buffer(M.prev_buf) then
    table.insert(M.switch_history, { bufnr = M.prev_buf, path = prev_path })
  end

  -- 添加其他 buffer，基于路径去重，限制最多 10 项
  local seen_paths = {
    [current_path] = true,
    [prev_path] = true,
  }
  for _, entry in ipairs(other_bufs) do
    if entry.bufnr ~= M.prev_buf and not seen_paths[entry.path] and #M.switch_history < 10 then
      table.insert(M.switch_history, entry)
      seen_paths[entry.path] = true
    end
  end

  -- 如果当前 buffer 不可编辑，selection 从 1 开始（上一个），否则从 2 开始
  M.selection = current_is_editable and 2 or 1
  M.active = true

  M.buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.buf_id, "filetype", "buffer-switcher")
  vim.api.nvim_buf_set_option(M.buf_id, "syntax", "") -- 禁用语法高亮干扰

  local width = 50 -- 加宽以显示完整路径
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

  local entry = M.switch_history[M.selection]
  local target_buf = entry and entry.bufnr

  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    -- 切换后，prev_buf 设为刚切换到的 buffer
    M.prev_buf = target_buf
    vim.api.nvim_set_current_buf(target_buf)
  end
  M.close()
end

function M.setup()
  -- 定义高亮配色
  vim.api.nvim_set_hl(0, "BufferSwitcherName", { fg = "#e4e4e4", bold = true })

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
