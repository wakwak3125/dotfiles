require("config.lazy")

-- 基本項目
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

-- 検索
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.keymap.set('n', '<Esc><Esc>', '<Cmd>nohlsearch<CR><Esc>', { silent = true })

vim.keymap.set('n', 'j', 'gj', { noremap = true, silent = true })
vim.keymap.set('n', 'k', 'gk', { noremap = true, silent = true })

local function is_wsl()
  if vim.env.WSL_DISTRO_NAME ~= nil or vim.env.WSL_INTEROP ~= nil then
    return true
  end

  local file = io.open("/proc/sys/kernel/osrelease", "r")
  if file == nil then
    return false
  end
  local release = string.lower(file:read("*a"))
  file:close()
  return string.find(release, "microsoft") ~= nil or string.find(release, "wsl") ~= nil
end

if is_wsl() then
  if vim.fn.executable("win32yank.exe") == 1 then
    vim.g.clipboard = {
      name = "win32yank-wsl",
      copy = {
        ["+"] = { "win32yank.exe", "-i", "--crlf" },
        ["*"] = { "win32yank.exe", "-i", "--crlf" },
      },
      paste = {
        ["+"] = { "win32yank.exe", "-o", "--lf" },
        ["*"] = { "win32yank.exe", "-o", "--lf" },
      },
      cache_enabled = 0,
    }
  elseif vim.fn.executable("clip.exe") == 1 and vim.fn.executable("powershell.exe") == 1 then
    vim.g.clipboard = {
      name = "windows-clipboard-wsl",
      copy = {
        ["+"] = { "clip.exe" },
        ["*"] = { "clip.exe" },
      },
      paste = {
        ["+"] = { "powershell.exe", "-NoLogo", "-NoProfile", "-Command", "Get-Clipboard" },
        ["*"] = { "powershell.exe", "-NoLogo", "-NoProfile", "-Command", "Get-Clipboard" },
      },
      cache_enabled = 0,
    }
  end
elseif vim.fn.has("mac") == 0 and vim.env.DISPLAY == nil and vim.env.WAYLAND_DISPLAY == nil then
  -- xclip や wl-copy が入っていても DISPLAY がないと provider が見つからず yank が捨てられるため、OSC 52 で手元の端末へ送る
  local osc52 = require("vim.ui.clipboard.osc52")
  -- OSC 52 の読み出しは応答しない端末があり貼り付けが固まるため、貼り付けは nvim のレジスタから行う
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "osc52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = paste,
      ["*"] = paste,
    },
  }
end

vim.opt.clipboard = "unnamedplus"
