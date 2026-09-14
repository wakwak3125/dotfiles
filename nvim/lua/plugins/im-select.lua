-- macOS: macism / Linux (Ubuntu GNOME 等): ibus で、ノーマルモード復帰時に英字入力へ戻す
local is_mac = vim.fn.has("mac") == 1

return {
  "keaising/im-select.nvim",
  enabled = is_mac or vim.fn.executable("ibus") == 1,
  event = "VeryLazy",
  opts = {
    default_im_select = is_mac and "com.apple.keylayout.ABC" or "xkb:us::eng",
    default_command = is_mac and "macism" or "ibus",
    set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
    set_previous_events = {},
  },
}
