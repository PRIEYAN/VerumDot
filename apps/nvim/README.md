# nvim — VS Code layout, glass panes

An overlay, not a config. Two symlinks drop it onto any
[lazy.nvim](https://github.com/folke/lazy.nvim) setup; everything already in
`~/.config/nvim` keeps working.

```
explorer │ tabs ─────────────────────────────────────
  left   │ code
  rail   │
         ├──────────────────────────────────────────
         │ terminal        Ctrl+Shift+`
```

## Keys

| Bind | Action |
|------|--------|
| `Ctrl` + `Shift` + `` ` `` | Toggle the terminal dock (also `Ctrl` + `` ` ``) |
| `Ctrl` + `B` | Toggle the explorer |
| `SPACE` + `e` | Focus the explorer |
| `SPACE` + `tt` | Toggle the terminal dock |
| `Esc` `Esc` | Leave terminal mode |

The dock keeps one shell for the whole session — hiding it does not kill what
is running, and reopening lands you back in the same scrollback at the same
height you last dragged it to.

## How the glass works

Neovim cannot make anything transparent. Kitty can, but only for the *default*
background — a cell carrying an explicit colour is drawn solid, which is why
naive "transparent" configs end up with an opaque sidebar floating on a clear
editor.

So the four panes are painted four near-blacks, and kitty is told to treat
exactly those four as see-through, each at its own opacity:

| Pane | Colour | Opacity |
|------|--------|---------|
| Editor | `#010104` | 0.60 |
| Explorer | `#050509` | 0.70 |
| Terminal dock | `#08080d` | 0.74 |
| Tabline / statusline | `#0b0b11` | 0.80 |

Denser panes read as sitting further forward. The colours live in
[`lua/verum/palette.lua`](lua/verum/palette.lua) and must match
`transparent_background_colors` in [`../kitty/kitty.conf`](../kitty/kitty.conf)
— change one without the other and that pane goes solid.

Three more things keep text readable through it all:

- `hypr.conf` pins kitty's window opacity to `1.0`, so the compositor does not
  dim panes that are already translucent.
- `winblend`/`pumblend` stay at `0`. They blend against Neovim's own
  background, which is transparent already; stacking the two turns text to fog.
- Comments, line numbers and inactive tabs are lit well above the usual dim
  greys, and kitty's `dim_opacity` is raised to `0.78`.

## Layout

- **Explorer** opens on the first real file of a session and leaves the cursor
  in the code. Dotfiles are visible, the root node is shown, selection follows
  the buffer you are editing. A dashboard, a commit message or a man page does
  not trigger it.
- **Tabs** are square. Slanted separators leave wedges of a second background
  colour, and two translucent blacks meeting at an angle read as a seam.
- **The dock** splits below the editor column, not the whole window, so it
  starts where the explorer ends — the way VS Code's panel does.

## Files

```
lua/
├── plugins/verum.lua    # lazy spec: neo-tree + bufferline overrides
└── verum/
    ├── init.lua         # entry point, fixes load order
    ├── palette.lua      # the four pane colours + the ink
    ├── options.lua      # the options the layout depends on
    ├── glass.lua        # every highlight group, re-applied on ColorScheme
    ├── explorer.lua     # when the rail opens
    └── panel.lua        # the terminal dock
```

## Install

`setup.sh` does it (`--no-nvim` to opt out). By hand:

```sh
ln -sfn ~/.config/hypr/apps/nvim/lua/verum             ~/.config/nvim/lua/verum
ln -sfn ~/.config/hypr/apps/nvim/lua/plugins/verum.lua ~/.config/nvim/lua/plugins/verum.lua
```

Then restart Neovim. There is nothing to install — the overlay only configures
`neo-tree` and `bufferline`, both of which LazyVim already ships.

## Notes

- `Ctrl+Shift+` `` ` `` reaches Neovim over the kitty keyboard protocol, which
  kitty and Neovim 0.10+ negotiate between themselves. On a terminal that
  cannot tell the two apart, `Ctrl+` `` ` `` is bound to the same thing.
- The dock's buffer carries a private filetype rather than `terminal`, because
  `edgy.nvim` (LazyVim's `ui.edgy` extra) claims every terminal-filetype window
  for its own bottom edge and would re-parent it mid-toggle.
- `Ctrl+B` is normally page-up. `Ctrl+U` still scrolls if you want it back,
  remove the mapping at the end of `lua/verum/explorer.lua`.
