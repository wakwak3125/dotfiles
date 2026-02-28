return {
  "keaising/im-select.nvim",
  enabled = vim.fn.has("mac") == 1,
  event = "VeryLazy",
  opts = {
    default_im_select = "com.apple.keylayout.ABC",
    default_command = "macism",
    set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
    set_previous_events = {},
  },
}
