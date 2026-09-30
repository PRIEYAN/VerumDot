--
--  VerumDot · nvim layout
--
--  Loaded by lazy.nvim from lua/plugins. The require below runs while specs
--  are still being collected, which is deliberate: the overlay only registers
--  autocmds and keymaps, and they have to exist before VimEnter fires.
--
require("verum").setup()

local P = require("verum.palette")

return {
  ---------------------------------------------------------------------------
  --  Explorer — left rail, VS Code rules: dotfiles visible, root shown,
  --  selection follows the file you are editing.
  ---------------------------------------------------------------------------
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      close_if_last_window = true,
      hide_root_node = false,
      popup_border_style = "rounded",
      window = {
        position = "left",
        width = 32,
        mappings = {
          --  Single click opens, the way the sidebar behaves everywhere else.
          ["<2-LeftMouse>"] = "open",
          ["<cr>"] = "open",
        },
      },
      filesystem = {
        --  Follow :cd so the rail always shows the project you are in, which
        --  matters here because init.lua sets autochdir.
        bind_to_cwd = true,
        cwd_target = { sidebar = "tab", current = "window" },
        follow_current_file = { enabled = true, leave_dirs_open = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_hidden = false,
          hide_by_name = { "node_modules", ".git" },
        },
      },
      default_component_configs = {
        indent = { with_expanders = true, indent_size = 2 },
        git_status = { align = "right" },
      },
    },
  },

  ---------------------------------------------------------------------------
  --  Tabs — square, not slanted. Slants leave wedges of a second background
  --  colour, and two translucent blacks meeting at an angle look like a seam.
  ---------------------------------------------------------------------------
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        mode = "buffers",
        separator_style = "thin",
        always_show_bufferline = true,
        show_buffer_close_icons = true,
        show_close_icon = false,
        diagnostics = "nvim_lsp",
        indicator = { style = "underline" },
        tab_size = 18,
        offsets = {
          {
            filetype = "neo-tree",
            text = "EXPLORER",
            text_align = "left",
            separator = true,
            highlight = "BufferLineNeoTree",
          },
        },
      },
      highlights = {
        fill = { bg = P.bar },
        background = { fg = P.fg_mute, bg = P.bar },
        buffer_visible = { fg = P.fg_dim, bg = P.bar },
        buffer_selected = { fg = P.white, bg = P.editor, bold = true, italic = false },
        separator = { fg = P.bar, bg = P.bar },
        separator_visible = { fg = P.bar, bg = P.bar },
        separator_selected = { fg = P.bar, bg = P.editor },
        indicator_selected = { fg = P.white, bg = P.editor },
        offset_separator = { fg = P.line, bg = P.bar },
      },
    },
  },

}
