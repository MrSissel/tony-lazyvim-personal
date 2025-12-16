-- LSP 配置 - 覆盖默认键映射
return {
  "neovim/nvim-lspconfig",
  opts = {
    -- 覆盖所有 LSP 服务
    servers = {
      ["*"] = {
        keys = {
          -- 禁用默认的 K 键映射（hover）
          { "K", false },
          -- 如果你想要保留 hover 功能，可以映射到其他键，比如 gh
          -- { "gh", vim.lsp.buf.hover, desc = "显示光标处的悬停信息" },
        },
      },
    },
  },
}

