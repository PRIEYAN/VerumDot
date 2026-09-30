--
--  VerumDot · explorer
--
--  VS Code shows the tree the moment a project is open, and the cursor is in
--  the code, not the sidebar. Neo-tree's own `:Neotree show` does exactly
--  that — open without stealing focus — so all this does is decide *when*.
--
--    nvim <file>   → tree opens beside it on VimEnter
--    nvim <dir>    → LazyVim already hands the directory to neo-tree
--    nvim          → dashboard stays clean; the tree appears with the first
--                    real file that gets opened
--
local M = {}

--  Buffers that are a task rather than a project: a commit message, a man
--  page, a diff from `git difftool`. A sidebar is noise in all of them.
local SKIP_FT = {
  ["gitcommit"] = true,
  ["gitrebase"] = true,
  ["help"] = true,
  ["man"] = true,
  ["qf"] = true,
  ["alpha"] = true,
  ["dashboard"] = true,
  ["snacks_dashboard"] = true,
  ["TelescopePrompt"] = true,
  ["lazy"] = true,
  ["mason"] = true,
}

local function is_project_buf(buf)
  buf = buf or 0
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  if SKIP_FT[vim.bo[buf].filetype] then
    return false
  end
  return vim.api.nvim_buf_get_name(buf) ~= ""
end

local function show()
  if vim.g.verum_tree_shown then
    return
  end

  --  neo-tree is lazy-loaded, so :Neotree does not exist yet on the very
  --  first file of a session. Pull the plugin in first and drive it through
  --  its Lua command module rather than waiting for the user command to be
  --  registered.
  local ok, cmd = pcall(require, "neo-tree.command")
  if not ok then
    pcall(function()
      require("lazy").load({ plugins = { "neo-tree.nvim" } })
    end)
    ok, cmd = pcall(require, "neo-tree.command")
  end
  if not ok then
    return
  end

  --  action = "show" opens the rail without taking the cursor out of the
  --  code, which is the whole point.
  pcall(cmd.execute, { action = "show", source = "filesystem", position = "left" })
  vim.g.verum_tree_shown = true
end

function M.setup()
  local group = vim.api.nvim_create_augroup("VerumExplorer", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    nested = true,
    callback = function()
      --  `nvim file` — argc is already resolved here. `nvim .` is left to
      --  LazyVim, which hijacks the directory buffer with neo-tree itself.
      if vim.fn.argc() == 0 then
        return
      end
      if vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
        vim.g.verum_tree_shown = true
        return
      end
      vim.schedule(show)
    end,
  })

  --  Bare `nvim`: wait for the dashboard to hand over to a real file.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    nested = true,
    callback = function(args)
      if vim.g.verum_tree_shown or not is_project_buf(args.buf) then
        return
      end
      vim.schedule(show)
    end,
  })

  --  Toggling by hand should not be undone by the next file that opens.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "neo-tree",
    callback = function()
      vim.g.verum_tree_shown = true
    end,
  })

  vim.keymap.set("n", "<C-b>", "<Cmd>Neotree toggle left<CR>", { silent = true, desc = "Toggle explorer" })
  vim.keymap.set("n", "<leader>e", "<Cmd>Neotree focus left<CR>", { silent = true, desc = "Focus explorer" })
end

return M
