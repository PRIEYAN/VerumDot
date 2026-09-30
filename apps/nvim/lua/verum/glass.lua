--
--  VerumDot · nvim glass
--
--  Four translucent panes — explorer, editor, panel, bars — each a slightly
--  different black so the layers read apart when the wallpaper shows through.
--  The transparency itself is kitty's job (see palette.lua); this file only
--  makes sure every highlight group agrees on which pane it belongs to, and
--  that the ink stays hot enough to survive a busy wallpaper behind it.
--
local P = require("verum.palette")

local M = {}

local function set(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

local function num(hex)
  return tonumber(hex:sub(2), 16)
end

--  Colourschemes paint their own background onto dozens of groups. Left alone
--  those become opaque islands in the glass, so anything wearing the old
--  background gets the editor tint instead. Links are skipped — following one
--  would flatten it into a copy and break the scheme's own inheritance.
local function retint()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local old = normal.bg
  if not old then
    return
  end
  local editor = num(P.editor)
  if old == editor then
    return
  end
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    if def.bg == old and not def.link then
      def.bg = editor
      pcall(vim.api.nvim_set_hl, 0, name, def)
    end
  end
end

function M.apply()
  retint()

  ---------------------------------------------------------------------------
  --  Editor pane
  ---------------------------------------------------------------------------
  set("Normal", { fg = P.fg, bg = P.editor })
  set("NormalNC", { fg = P.fg, bg = P.editor })
  set("EndOfBuffer", { fg = P.editor, bg = P.editor })
  set("SignColumn", { bg = P.editor })
  set("FoldColumn", { fg = P.fg_mute, bg = P.editor })
  set("MsgArea", { fg = P.fg, bg = P.editor })
  set("MsgSeparator", { fg = P.line, bg = P.editor })
  set("VertSplit", { fg = P.line, bg = P.editor })
  set("WinSeparator", { fg = P.line, bg = P.editor })

  set("LineNr", { fg = P.fg_mute, bg = P.editor })
  set("LineNrAbove", { fg = P.fg_mute, bg = P.editor })
  set("LineNrBelow", { fg = P.fg_mute, bg = P.editor })
  set("CursorLineNr", { fg = P.white, bg = P.cursor, bold = true })
  set("CursorLine", { bg = P.cursor })
  set("CursorColumn", { bg = P.cursor })
  set("ColorColumn", { bg = P.cursor })
  set("Cursor", { fg = P.editor, bg = P.white })
  set("TermCursor", { fg = P.panel, bg = P.white })

  set("Visual", { bg = P.sel })
  set("VisualNOS", { bg = P.sel })
  set("Search", { fg = P.white, bg = P.match, bold = true })
  set("IncSearch", { fg = P.editor, bg = P.yellow, bold = true })
  set("CurSearch", { fg = P.editor, bg = P.yellow, bold = true })
  set("MatchParen", { fg = P.white, bg = P.match, bold = true })

  --  Comments are the first thing a wallpaper swallows. Keep them lit.
  set("Comment", { fg = P.fg_mute, italic = true })
  set("NonText", { fg = P.line })
  set("Whitespace", { fg = P.line })
  set("SpecialKey", { fg = P.line })
  set("Conceal", { fg = P.fg_mute })
  set("Folded", { fg = P.fg_dim, bg = P.cursor })

  ---------------------------------------------------------------------------
  --  Explorer pane
  ---------------------------------------------------------------------------
  local tree = { fg = P.fg_dim, bg = P.sidebar }
  for _, g in ipairs({
    "NeoTreeNormal",
    "NeoTreeNormalNC",
    "NeoTreeEndOfBuffer",
    "NeoTreeSignColumn",
    "NeoTreeStatusLine",
    "NeoTreeStatusLineNC",
    "NeoTreeVertSplit",
  }) do
    set(g, tree)
  end
  set("NeoTreeWinSeparator", { fg = P.line, bg = P.sidebar })
  set("NeoTreeFileName", { fg = P.fg_dim, bg = P.sidebar })
  set("NeoTreeFileNameOpened", { fg = P.white, bg = P.sidebar, bold = true })
  set("NeoTreeDirectoryName", { fg = P.fg, bg = P.sidebar })
  set("NeoTreeDirectoryIcon", { fg = P.fg_dim, bg = P.sidebar })
  set("NeoTreeRootName", { fg = P.white, bg = P.sidebar, bold = true })
  set("NeoTreeIndentMarker", { fg = P.line, bg = P.sidebar })
  set("NeoTreeExpander", { fg = P.fg_mute, bg = P.sidebar })
  set("NeoTreeCursorLine", { bg = P.sel, bold = true })
  set("NeoTreeTitleBar", { fg = P.white, bg = P.bar, bold = true })
  set("NeoTreeFloatTitle", { fg = P.white, bg = P.panel, bold = true })
  set("NeoTreeFloatBorder", { fg = P.line, bg = P.panel })
  set("NeoTreeFloatNormal", { fg = P.fg, bg = P.panel })
  set("NeoTreeGitModified", { fg = P.yellow, bg = P.sidebar })
  set("NeoTreeGitAdded", { fg = P.green, bg = P.sidebar })
  set("NeoTreeGitDeleted", { fg = P.red, bg = P.sidebar })
  set("NeoTreeGitUntracked", { fg = P.green, bg = P.sidebar, italic = true })
  set("NeoTreeGitIgnored", { fg = P.fg_mute, bg = P.sidebar })
  set("NeoTreeDimText", { fg = P.fg_mute, bg = P.sidebar })
  set("NeoTreeModified", { fg = P.yellow, bg = P.sidebar })

  --  edgy owns the left edge under LazyVim's ui extra — dress its chrome too.
  set("EdgyNormal", { fg = P.fg_dim, bg = P.sidebar })
  set("EdgyWinBar", { fg = P.white, bg = P.bar, bold = true })
  set("EdgyTitle", { fg = P.white, bg = P.bar, bold = true })
  set("EdgyIcon", { fg = P.fg_dim, bg = P.bar })
  set("EdgyIconActive", { fg = P.white, bg = P.bar })

  ---------------------------------------------------------------------------
  --  Bottom panel  (see verum/panel.lua — the window wears these via
  --  'winhighlight', which is why they are named rather than linked)
  ---------------------------------------------------------------------------
  set("VerumPanel", { fg = P.fg, bg = P.panel })
  set("VerumPanelNC", { fg = P.fg_dim, bg = P.panel })
  set("VerumPanelSeparator", { fg = P.line, bg = P.panel })
  set("VerumPanelTitle", { fg = P.white, bg = P.bar, bold = true })
  set("VerumPanelTitleDim", { fg = P.fg_mute, bg = P.bar })

  ---------------------------------------------------------------------------
  --  Bars: tabline, statusline, winbar
  ---------------------------------------------------------------------------
  set("TabLineFill", { bg = P.bar })
  set("TabLine", { fg = P.fg_mute, bg = P.bar })
  set("TabLineSel", { fg = P.white, bg = P.editor, bold = true })
  set("StatusLine", { fg = P.fg_dim, bg = P.bar })
  set("StatusLineNC", { fg = P.fg_mute, bg = P.bar })
  set("WinBar", { fg = P.fg_dim, bg = P.bar })
  set("WinBarNC", { fg = P.fg_mute, bg = P.bar })

  --  bufferline: VS Code tabs — active tab is a cut-out of the editor pane,
  --  inactive tabs sit back in the bar.
  set("BufferLineFill", { bg = P.bar })
  set("BufferLineBackground", { fg = P.fg_mute, bg = P.bar })
  set("BufferLineBufferVisible", { fg = P.fg_dim, bg = P.bar })
  set("BufferLineBufferSelected", { fg = P.white, bg = P.editor, bold = true, italic = false })
  set("BufferLineSeparator", { fg = P.bar, bg = P.bar })
  set("BufferLineSeparatorVisible", { fg = P.bar, bg = P.bar })
  set("BufferLineSeparatorSelected", { fg = P.bar, bg = P.editor })
  set("BufferLineIndicatorSelected", { fg = P.white, bg = P.editor })
  set("BufferLineIndicatorVisible", { fg = P.bar, bg = P.bar })
  set("BufferLineModified", { fg = P.yellow, bg = P.bar })
  set("BufferLineModifiedVisible", { fg = P.yellow, bg = P.bar })
  set("BufferLineModifiedSelected", { fg = P.yellow, bg = P.editor })
  set("BufferLineCloseButton", { fg = P.fg_mute, bg = P.bar })
  set("BufferLineCloseButtonVisible", { fg = P.fg_mute, bg = P.bar })
  set("BufferLineCloseButtonSelected", { fg = P.white, bg = P.editor })
  set("BufferLineNeoTree", { fg = P.white, bg = P.bar, bold = true })
  set("BufferLineOffsetSeparator", { fg = P.line, bg = P.bar })

  ---------------------------------------------------------------------------
  --  Floats, menus, pickers
  ---------------------------------------------------------------------------
  set("NormalFloat", { fg = P.fg, bg = P.panel })
  set("FloatBorder", { fg = P.line, bg = P.panel })
  set("FloatTitle", { fg = P.white, bg = P.panel, bold = true })
  set("Pmenu", { fg = P.fg_dim, bg = P.panel })
  set("PmenuSel", { fg = P.white, bg = P.sel, bold = true })
  set("PmenuSbar", { bg = P.panel })
  set("PmenuThumb", { bg = P.sel })
  set("WildMenu", { fg = P.white, bg = P.sel })
  set("QuickFixLine", { bg = P.sel, bold = true })

  for _, g in ipairs({
    "TelescopeNormal",
    "TelescopePromptNormal",
    "TelescopeResultsNormal",
    "TelescopePreviewNormal",
    "SnacksNormal",
    "SnacksPickerNormal",
    "NoiceCmdlinePopup",
    "NoicePopup",
    "NotifyBackground",
    "WhichKeyNormal",
    "LspSagaNormal",
    "TroubleNormal",
  }) do
    set(g, { fg = P.fg, bg = P.panel })
  end
  for _, g in ipairs({
    "TelescopeBorder",
    "TelescopePromptBorder",
    "TelescopeResultsBorder",
    "TelescopePreviewBorder",
    "SnacksPickerBorder",
    "NoiceCmdlinePopupBorder",
    "WhichKeyBorder",
    "LspSagaBorder",
  }) do
    set(g, { fg = P.line, bg = P.panel })
  end
  set("TelescopeSelection", { fg = P.white, bg = P.sel, bold = true })
  set("TelescopeMatching", { fg = P.yellow, bold = true })

  ---------------------------------------------------------------------------
  --  Diagnostics & git — colour is the only thing carrying meaning here, so
  --  none of it gets a background that would trap it in an opaque box.
  ---------------------------------------------------------------------------
  set("DiagnosticError", { fg = P.red })
  set("DiagnosticWarn", { fg = P.yellow })
  set("DiagnosticInfo", { fg = P.blue })
  set("DiagnosticHint", { fg = P.cyan })
  set("DiagnosticOk", { fg = P.green })
  set("DiagnosticVirtualTextError", { fg = P.red, bg = "NONE", italic = true })
  set("DiagnosticVirtualTextWarn", { fg = P.yellow, bg = "NONE", italic = true })
  set("DiagnosticVirtualTextInfo", { fg = P.blue, bg = "NONE", italic = true })
  set("DiagnosticVirtualTextHint", { fg = P.cyan, bg = "NONE", italic = true })

  set("DiffAdd", { fg = P.green, bg = "NONE" })
  set("DiffChange", { fg = P.yellow, bg = "NONE" })
  set("DiffDelete", { fg = P.red, bg = "NONE" })
  set("DiffText", { fg = P.white, bg = P.sel })
  set("GitSignsAdd", { fg = P.green, bg = P.editor })
  set("GitSignsChange", { fg = P.yellow, bg = P.editor })
  set("GitSignsDelete", { fg = P.red, bg = P.editor })

  ---------------------------------------------------------------------------
  --  :terminal palette — the bottom panel runs a real shell, and the default
  --  ANSI blacks/greys are unreadable once a wallpaper is behind them.
  ---------------------------------------------------------------------------
  local term = {
    P.line, P.red, P.green, P.yellow, P.blue, P.magenta, P.cyan, P.fg_dim,
    P.sel, P.red, P.green, P.yellow, P.blue, P.magenta, P.cyan, P.white,
  }
  for i, colour in ipairs(term) do
    vim.g["terminal_color_" .. (i - 1)] = colour
  end
end

function M.setup()
  --  Blend must stay off: it mixes a window with Neovim's idea of the
  --  background, which is already translucent. Stacking the two turns text
  --  into fog — exactly the thing this config exists to avoid.
  vim.opt.winblend = 0
  vim.opt.pumblend = 0
  vim.opt.termguicolors = true

  local group = vim.api.nvim_create_augroup("VerumGlass", { clear = true })

  --  Twice on purpose. Some schemes (neopywal among them, which is what this
  --  rice ships) finish painting in a deferred pass after the ColorScheme
  --  event, so a single synchronous re-apply loses the race about half the
  --  time and the editor pane comes up with the scheme's own background.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.apply()
      vim.schedule(M.apply)
    end,
  })

  --  Startup order is not fixed either: lazy.nvim can yield to the event loop
  --  mid-setup, so the scheme may land before or after this file is read.
  vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, {
    group = group,
    callback = function()
      vim.defer_fn(M.apply, 30)
    end,
  })

  vim.schedule(M.apply)
end

return M
