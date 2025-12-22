return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        files = {
          hidden = true, -- 默认显示隐藏文件
          ignored = false, -- 不忽略 .gitignore 中的文件
        },
        grep = {
          hidden = true, -- 在 grep 中也显示隐藏文件
          ignored = false,
        },
        explorer = {
          hidden = true, -- 在 explorer 中默认显示隐藏文件
          ignored = false,
        },
      },
    },
    explorer = {
      -- 启用 explorer 替换 netrw
      replace_netrw = true,
      -- 使用系统垃圾箱
      trash = true,
    },
  },
}

