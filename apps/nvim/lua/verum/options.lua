--
--  VerumDot · editor options
--
--  Only the ones the VS Code layout depends on. Everything else is left to
--  LazyVim so this overlay stays droppable on top of any config.
--
local M = {}

function M.setup()
  local opt = vim.opt

  --  One statusline across the bottom instead of one per split — without it
  --  every split grows its own bar and the glass turns into stripes.
  opt.laststatus = 3
  opt.showmode = false
  opt.cmdheight = 0

  --  Gutter: absolute numbers, and a signcolumn that is always there so the
  --  code does not shift sideways when a diagnostic appears.
  opt.number = true
  opt.relativenumber = false
  opt.signcolumn = "yes"
  opt.cursorline = true
  opt.cursorlineopt = "both"

  opt.wrap = false
  opt.scrolloff = 6
  opt.sidescrolloff = 8
  opt.splitbelow = true
  opt.splitright = true
  opt.termguicolors = true
  opt.mouse = "a"
  opt.mousemoveevent = true

  --  Thin, low-contrast structure marks. Anything heavier competes with the
  --  wallpaper showing through the pane.
  opt.fillchars = {
    eob = " ",
    vert = "│",
    horiz = "─",
    horizup = "┴",
    horizdown = "┬",
    vertleft = "┤",
    vertright = "├",
    verthoriz = "┼",
    fold = " ",
    foldopen = "▾",
    foldclose = "▸",
    foldsep = "│",
    diff = "╱",
  }
end

return M
