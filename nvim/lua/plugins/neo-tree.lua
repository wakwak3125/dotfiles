return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  keys = {
    { "<leader>e", ":Neotree toggle<CR>", desc = "Neo-tree Toggle" },
    { "<leader>E", ":Neotree reveal<CR>", desc = "Neo-tree Reveal Current" },
  },
  opts = {
    window = { position = "left", width = 34 },
    filesystem = {
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true, -- WSLでも変更検知が安定
      filtered_items = { hide_dotfiles = false, hide_gitignored = true },
    },
    default_component_configs = {
      git_status = { symbols = { added = "A", modified = "M", deleted = "D" } },
    },
    enable_git_status = true,
  },
}

