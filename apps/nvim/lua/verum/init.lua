--
--  VerumDot · nvim overlay
--
--  A VS Code shaped Neovim: explorer left, tabs on top, code in the middle,
--  a terminal that docks at the bottom on Ctrl+Shift+`, all of it glass.
--
--  Entry point. Loaded from lua/plugins/verum.lua so the pieces come up in a
--  fixed order: options before highlights, highlights before the windows that
--  wear them.
--
local M = {}

function M.setup()
  require("verum.options").setup()
  require("verum.glass").setup()
  require("verum.panel").setup()
  require("verum.explorer").setup()
end

return M
