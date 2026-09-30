--
--  VerumDot · bottom panel
--
--  One terminal, docked under the editor column, toggled with Ctrl+Shift+`.
--  It is a plain window split rather than a float so the glass layers stack
--  the way VS Code's do: explorer beside it, editor above it, no shadow.
--
--  The buffer keeps a custom filetype instead of 'terminal'. edgy.nvim (via
--  LazyVim's ui extra) claims every terminal-filetype window for its own
--  bottom edge, which would re-parent this one mid-toggle and drop the
--  window-local colours. A private filetype keeps edgy out of it.
--
local M = {}

local HEIGHT = 14
local FILETYPE = "verumpanel"

local state = { buf = nil, win = nil, height = HEIGHT }

local WINHL = table.concat({
  "Normal:VerumPanel",
  "NormalNC:VerumPanelNC",
  "SignColumn:VerumPanel",
  "EndOfBuffer:VerumPanel",
  "WinSeparator:VerumPanelSeparator",
  "VertSplit:VerumPanelSeparator",
  "WinBar:VerumPanelTitle",
  "WinBarNC:VerumPanelTitle",
}, ",")

local function win_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function buf_alive()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

--  Splitting from the explorer would dock the panel under the tree instead of
--  under the code, so hop to a normal window first.
local function goto_editor_win()
  local ft = vim.bo.filetype
  if ft ~= "neo-tree" and ft ~= FILETYPE then
    return true
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bft = vim.bo[buf].filetype
    if bft ~= "neo-tree" and bft ~= FILETYPE and vim.bo[buf].buftype ~= "prompt" then
      vim.api.nvim_set_current_win(win)
      return true
    end
  end
  return false
end

local function dress(win)
  vim.wo[win].winhighlight = WINHL
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].winfixheight = true
  vim.wo[win].list = false
  vim.wo[win].spell = false
  vim.wo[win].winbar = "%#VerumPanelTitle#  TERMINAL %#VerumPanelTitleDim#· Ctrl+Shift+` to hide %*"
end

function M.open(focus)
  if win_open() then
    if focus ~= false then
      vim.api.nvim_set_current_win(state.win)
      vim.cmd("startinsert")
    end
    return
  end

  local from = vim.api.nvim_get_current_win()
  goto_editor_win()

  --  Never let the dock eat the editor on a short window or a half-height
  --  Hyprland tile — 40% of what is available is the ceiling.
  local room = math.max(4, math.floor(vim.api.nvim_win_get_height(0) * 0.4))
  vim.cmd("belowright " .. math.min(state.height, room) .. "split")
  state.win = vim.api.nvim_get_current_win()

  if buf_alive() then
    vim.api.nvim_win_set_buf(state.win, state.buf)
  else
    --  :terminal inherits the cwd, so the shell lands where the editor is.
    vim.cmd("terminal")
    state.buf = vim.api.nvim_get_current_buf()
    vim.bo[state.buf].buflisted = false
    vim.bo[state.buf].filetype = FILETYPE
    vim.b[state.buf].verum_panel = true

    --  Closing the shell closes the dock rather than leaving a dead buffer.
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = state.buf,
      callback = function()
        state.buf = nil
        vim.schedule(M.close)
      end,
    })
  end

  dress(state.win)

  if focus == false then
    if vim.api.nvim_win_is_valid(from) then
      vim.api.nvim_set_current_win(from)
    end
  else
    vim.cmd("startinsert")
  end
end

function M.close()
  if not win_open() then
    state.win = nil
    return
  end
  --  Remember the height the user dragged it to.
  state.height = vim.api.nvim_win_get_height(state.win)
  if vim.api.nvim_get_current_win() == state.win then
    vim.cmd("stopinsert")
  end
  --  hide, not close: the shell and its scrollback survive the toggle.
  pcall(vim.api.nvim_win_hide, state.win)
  state.win = nil
end

function M.toggle()
  if win_open() then
    M.close()
  else
    M.open(true)
  end
end

--  Ctrl+Shift+` from inside the shell has to leave terminal mode before the
--  window calls can run, otherwise the keystroke is swallowed by the pty.
function M.toggle_from_term()
  vim.cmd("stopinsert")
  vim.schedule(M.toggle)
end

function M.setup()
  vim.opt.splitbelow = true
  vim.opt.splitright = true

  --  Ctrl+Shift+` reaches Neovim only over the kitty keyboard protocol, which
  --  kitty and Neovim 0.10+ negotiate on their own. Ctrl+` is bound to the
  --  same thing so the toggle still works on terminals that collapse the two.
  for _, key in ipairs({ "<C-S-`>", "<C-`>" }) do
    vim.keymap.set({ "n", "v" }, key, M.toggle, { silent = true, desc = "Toggle terminal panel" })
    vim.keymap.set("i", key, function()
      vim.cmd("stopinsert")
      M.toggle()
    end, { silent = true, desc = "Toggle terminal panel" })
    vim.keymap.set("t", key, M.toggle_from_term, { silent = true, desc = "Toggle terminal panel" })
  end

  vim.keymap.set("n", "<leader>tt", M.toggle, { silent = true, desc = "Toggle terminal panel" })

  --  Esc Esc drops to normal mode inside the shell; a single Esc still
  --  belongs to whatever is running in there.
  vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { silent = true, desc = "Terminal: normal mode" })

  --  Re-dress on entry: a colourscheme reload or an :edit can reset
  --  window-local highlights out from under the dock.
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("VerumPanel", { clear = true }),
    callback = function()
      if win_open() and vim.api.nvim_get_current_win() == state.win then
        dress(state.win)
      end
    end,
  })
end

return M
