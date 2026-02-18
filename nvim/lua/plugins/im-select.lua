-- macOS専用プラグイン: macOS以外では無効化
if vim.fn.has("mac") ~= 1 then
  return {}
end

return {
  "keaising/im-select.nvim",
  event = "VeryLazy",
  opts = {
    default_im_select = "com.apple.keylayout.ABC",
    default_command = "macism",
    set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
    set_previous_events = {},
  },
}
