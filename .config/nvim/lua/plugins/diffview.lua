-- Diffview: git diff viewer with side-by-side panels.
--
-- Keymap layout under <leader>gd* (pure prefix, no leaf to avoid timeout lag):
--   gdd    working tree vs HEAD  (the default "open diffview")
--   gdf    history of CURRENT FILE
--   gdv    history of VISUAL RANGE  (visual mode) — when did THESE lines change?
--   gdb    compare working tree vs another BRANCH (prompt)
--   gdr    compare working tree vs REF (HEAD~N, sha, tag — prompt)
--   gdh    repo-wide history (all commits)
--   gds    diff against a STASH (prompt)
--   gdc    close diffview
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
  keys = {
    {
      "<leader>gdd",
      function() require("diffview").open() end,
      desc = "Diffview: working tree vs HEAD",
    },
    {
      "<leader>gdf",
      "<cmd>DiffviewFileHistory %<cr>",
      desc = "Diffview: history of current file",
    },
    {
      "<leader>gdv",
      ":DiffviewFileHistory<cr>",
      mode = "v",
      desc = "Diffview: history of selected range",
    },
    {
      "<leader>gdb",
      function()
        vim.ui.input({ prompt = "Compare with branch: " }, function(branch)
          if branch and branch ~= "" then
            require("diffview").open(branch)
          end
        end)
      end,
      desc = "Diffview: compare branch",
    },
    {
      "<leader>gdr",
      function()
        vim.ui.input({ prompt = "Compare with ref (e.g. HEAD~3, sha, tag): " }, function(ref)
          if ref and ref ~= "" then
            require("diffview").open(ref)
          end
        end)
      end,
      desc = "Diffview: compare ref",
    },
    {
      "<leader>gdh",
      "<cmd>DiffviewFileHistory<cr>",
      desc = "Diffview: repo-wide history",
    },
    {
      "<leader>gds",
      function()
        vim.ui.input({ prompt = "Stash ref (e.g. stash@{0}): ", default = "stash@{0}" }, function(ref)
          if ref and ref ~= "" then
            require("diffview").open(ref .. "^.." .. ref)
          end
        end)
      end,
      desc = "Diffview: compare stash",
    },
    {
      "<leader>gdc",
      function() require("diffview").close() end,
      desc = "Diffview: close",
    },
  },
  opts = {
    enhanced_diff_hl = true,        -- use DiffText for inline byte-level changes
    use_icons = true,
    view = {
      merge_tool = {
        layout = "diff3_mixed",     -- 3-way layout for conflicts
        disable_diagnostics = true, -- LSP errors during merge are noise
      },
    },
  },
  config = function(_, opts)
    require("diffview").setup(opts)
    -- (No scrollbind autocmd: diffview's diff windows already sync via the
    -- built-in `diff` window option. Forcing scrollbind on every window broke
    -- file-history panel coroutines.)
  end,
}
