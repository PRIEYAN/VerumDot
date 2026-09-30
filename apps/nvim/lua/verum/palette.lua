--
--  VerumDot · nvim glass palette
--
--  Four pane tints, pure-black family. Each one is also listed in
--  apps/kitty/kitty.conf under `transparent_background_colors`, which is what
--  actually makes the pane see-through — Neovim only paints the colour, kitty
--  decides how much wallpaper shows through it. Change a value here and you
--  MUST change the matching one there, or that pane turns solid.
--
return {
  -- panes (must mirror kitty's transparent_background_colors)
  editor  = "#010104", -- code area          · kitty @ 0.60
  sidebar = "#050509", -- explorer           · kitty @ 0.70
  panel   = "#08080d", -- bottom terminal    · kitty @ 0.74
  bar     = "#0b0b11", -- tabline / status   · kitty @ 0.80

  -- ink — deliberately hot. Glass eats contrast, so nothing here is subtle.
  fg      = "#EDEDF2", -- body text
  fg_dim  = "#B9B9C6", -- secondary text (inactive tabs, tree files)
  fg_mute = "#8A8A9C", -- comments, line numbers — still legible over wallpaper
  white   = "#FFFFFF", -- current line number, active tab, cursor

  -- structure
  line    = "#23232F", -- separators, borders
  cursor  = "#14141D", -- cursorline wash
  sel     = "#2B2B3A", -- visual / menu selection
  match   = "#3A3A4D", -- search, matched paren

  -- states (kept bright for the same reason)
  red     = "#FF6B6B",
  green   = "#5EE89A",
  yellow  = "#FFD479",
  blue    = "#7AB8FF",
  magenta = "#E39BFF",
  cyan    = "#7FE7E0",
}
