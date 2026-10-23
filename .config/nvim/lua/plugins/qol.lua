-- Quality-of-life plugins: small additions that punch way above their weight.
--
-- Adds:
--   • nvim-treesitter-context  — sticky scope header (function/class) at top of window
--   • snacks.words             — highlights other instances of the symbol under cursor
--   • snacks.indent            — subtle indent guides + scope highlighting
--   • snacks.bigfile           — auto-disables expensive features on huge files
--   • grug-far.nvim keymap     — project-wide find/replace (you had it installed, unbound)
return {
  -- Sticky context header: shows the enclosing function/class/if at the top of
  -- the window when its opening line scrolls offscreen. Once you have it, going
  -- back feels like driving without a windshield.
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      max_lines = 4,            -- cap the sticky header height
      min_window_height = 20,   -- skip on tiny windows (e.g. terminal splits)
      multiline_threshold = 1,  -- collapse multiline signatures to 1 line
      mode = "cursor",          -- update based on cursor, not just scroll
      separator = nil,          -- set to "─" if you want a hairline under it
      trim_scope = "outer",     -- if too many parents, drop the outermost
    },
    keys = {
      {
        "<leader>uC",
        function()
          require("treesitter-context").toggle()
          vim.notify("Treesitter context " .. (require("treesitter-context").enabled() and "on" or "off"))
        end,
        desc = "Toggle treesitter context",
      },
      {
        "[c",
        function() require("treesitter-context").go_to_context(vim.v.count1) end,
        desc = "Jump to context (upwards)",
      },
    },
  },

  -- Snacks modules — already installed via LazyVim, just opting in.
  {
    "folke/snacks.nvim",
    opts = {
      -- Highlight other occurrences of the symbol/word under the cursor (LSP
      -- documentHighlight). VSCode-style "ghost" of related identifiers.
      words = {
        enabled = true,
        debounce = 200,
        notify_jump = false,
      },
      -- Indent guides + active scope underline. Subtle, not noisy.
      indent = {
        enabled = true,
        animate = { enabled = false }, -- skip the animation; static guides
        scope = {
          enabled = true,
          underline = false,
          only_current = true, -- only show scope highlight in the active window
        },
        chunk = { enabled = false }, -- chunk highlighting is too busy with capo-dark
      },
      -- Big file mode: disables LSP/treesitter/syntax for files >1.5MB so opening
      -- a giant log/JSON doesn't lock up.
      bigfile = { enabled = true, size = 1.5 * 1024 * 1024 },
    },
    keys = {
      -- Hop between adjacent occurrences of the word under cursor (when words
      -- highlighting is active). Like VSCode's F7 / Shift-F7.
      { "]]", function() Snacks.words.jump(vim.v.count1) end, desc = "Next word reference" },
      { "[[", function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev word reference" },
    },
  },

  -- grug-far: project-wide find/replace with live preview. You had it in your
  -- lock file but no keymap was bound.
  --   <leader>sR        replace across project (prefilled with cword if any)
  --   <leader>sR (vis)  replace using visual selection as the search term
  --   <leader>sw        replace word under cursor across project
  {
    "MagicDuck/grug-far.nvim",
    cmd = { "GrugFar" },
    keys = {
      {
        "<leader>sR",
        function()
          require("grug-far").open({
            prefills = { search = vim.fn.expand("<cword>") },
          })
        end,
        mode = "n",
        desc = "Search & replace (project)",
      },
      {
        "<leader>sR",
        function()
          require("grug-far").with_visual_selection()
        end,
        mode = "v",
        desc = "Search & replace (visual)",
      },
      {
        "<leader>sw",
        function()
          require("grug-far").open({
            prefills = { search = "\\b" .. vim.fn.expand("<cword>") .. "\\b", flags = "--fixed-strings=false" },
          })
        end,
        desc = "Search & replace word (project)",
      },
    },
    opts = {
      -- Use ripgrep; you almost certainly have it via fzf-lua already
      engine = "ripgrep",
      headerMaxWidth = 80,
      keymaps = {
        replace = { n = "<leader>r" },
        qflist = { n = "<leader>q" },
        syncLocations = { n = "<leader>s" },
        syncLine = { n = "<leader>l" },
        close = { n = "<leader>c" },
        historyOpen = { n = "<leader>t" },
        historyAdd = { n = "<leader>a" },
        refresh = { n = "<leader>f" },
        openLocation = { n = "<leader>o" },
        gotoLocation = { n = "<enter>" },
        pickHistoryEntry = { n = "<enter>" },
        abort = { n = "<leader>b" },
        help = { n = "g?" },
      },
    },
  },
}
