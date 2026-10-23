-- Keybind overrides:
--   <leader>f  → Find Files (Root Dir)       was <leader>ff
--   <leader>F  → Grep (Root Dir)              was <leader>sg / <leader>/
--   <leader>o  → "Open" group                  relocated from <leader>f + <leader>q groups
--   <leader>q  → Quit All (direct action)      was <leader>qq
--   <leader>L  → Wrap with Abbreviation (visual) was LazyVim Changelog
--
-- Everything previously under <leader>f is now under <leader>o:
--   <leader>of → Find Files (Root Dir)
--   <leader>oF → Find Files (cwd)
--   <leader>ob → Buffers
--   <leader>oB → Buffers (all)
--   <leader>oc → Find Config File
--   <leader>og → Git Files
--   <leader>or → Recent
--   <leader>oR → Recent (cwd)
--   <leader>op → Projects
--   <leader>oe → Explorer (Neo-tree)
--   <leader>oE → Explorer (cwd)
--   <leader>od → npm run dev terminal
--
-- Everything previously under <leader>q is now under <leader>o:
--   <leader>oq → Quit All
--   <leader>os → Restore Session (auto-session)
--   <leader>oS → Select Session (auto-session)
--   <leader>ol → Restore Last Session (auto-session)
--   <leader>oD → Don't Save Session (auto-session)
--
-- "Root Dir" = git repo root (climbs to .git)
-- "cwd"     = current working directory (could be backend/ subfolder)
-- We use Root Dir for both <leader>f and <leader>F.

return {
  -- ── Override which-key groups ──────────────────────────────────────────
  --
  -- <leader>f, <leader>q, <leader>w, <leader>L MUST be declared with
  -- group = false to prevent which-key from treating them as prefixes.
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>f", group = false, desc = "Find Files (Root Dir)", icon = "󰈞" },
        { "<leader>F", group = false, desc = "Grep (Root Dir)",        icon = "" },
        { "<leader>o", group = "open",                                 icon = "󰈔" },
        { "<leader>q", group = false, desc = "Quit All",                icon = "󰩈" },
        { "<leader>v", group = "viewport",                              icon = "󱂬" },
        { "<leader>w", group = false, desc = "Save file",            icon = "󰆓" },
        { "<leader>L", group = false, desc = "Wrap with Abbreviation", icon = "󰅴" },
      },
    },
  },

  -- ── LazyVim core overrides ─────────────────────────────────────────────
  -- Disable ALL <leader>q* sub-keys (persistence registers these separately
  -- and must be disabled here too, not just the LazyVim core ones).
  -- Also disable <leader>L (LazyVim Changelog) — now used by wrap-with-abbre5v.
  {
    "LazyVim",
    keys = {
      { "<leader>q",  "<cmd>qa<cr>",              desc = "Quit All", mode = "n" },
      { "<leader>qq", false },
      { "<leader>qs", false },
      { "<leader>qS", false },
      { "<leader>ql", false },
      { "<leader>qd", false },
      { "<leader>L",  false }, -- was LazyVim Changelog, now wrap-with-abbreviation
    },
  },
  -- Disable persistence.nvim entirely (replaced by auto-session)
  {
    "folke/persistence.nvim",
    enabled = false,
  },

  -- ── Override fzf-lua keybindings ───────────────────────────────────────
  -- These keys= overrides add our new bindings and disable old ones.
  -- Setting a key to `false` in lazy.nvim disables the parent spec's binding.
  --
  -- EVERY <leader>fX sub-key MUST be disabled here, otherwise which-key
  -- treats <leader>f as a group prefix and shows a menu instead of firing
  -- the direct action.
  {
    "ibhagwan/fzf-lua",
    optional = true,
    keys = {
      -- New direct shortcuts
      { "<leader>f",  "<cmd>FzfLua files<cr>",                                     desc = "Find Files (Root Dir)", mode = "n" },
      { "<leader>F",  "<cmd>FzfLua live_grep<cr>",                                desc = "Grep (Root Dir)",        mode = "n" },

      -- Disable ALL old <leader>f* sub-keys
      { "<leader>ff", false },
      { "<leader>fF", false },
      { "<leader>fb", false },
      { "<leader>fB", false },
      { "<leader>fc", false },
      { "<leader>fg", false },
      { "<leader>fr", false },
      { "<leader>fR", false },
      { "<leader>fp", false },
      { "<leader>fn", false },
      { "<leader>fe", false },
      { "<leader>fE", false },
      { "<leader>ft", false },
      { "<leader>fT", false },

      -- Disable old <leader>sg and <leader>/ (replaced by <leader>F)
      { "<leader>sg", false },
      { "<leader>/",  false },

      -- New <leader>o group — file/find entries (moved from <leader>f)
      { "<leader>of", "<cmd>FzfLua files<cr>",                                     desc = "Find Files (Root Dir)" },
      { "<leader>oF", "<cmd>FzfLua files cwd_only=true<cr>",                      desc = "Find Files (cwd)" },
      { "<leader>ob", "<cmd>FzfLua buffers sort_mru=true sort_lastused=true<cr>", desc = "Buffers" },
      { "<leader>oB", "<cmd>FzfLua buffers<cr>",                                    desc = "Buffers (all)" },
      { "<leader>oc", LazyVim.pick.config_files(),                                   desc = "Find Config File" },
      { "<leader>og", "<cmd>FzfLua git_files<cr>",                                  desc = "Git Files" },
      { "<leader>or", "<cmd>FzfLua oldfiles<cr>",                                   desc = "Recent" },
      { "<leader>oR", "<cmd>FzfLua oldfiles cwd_only=true<cr>",                    desc = "Recent (cwd)" },
      { "<leader>op", "<cmd>FzfLua projects<cr>",                                   desc = "Projects" },
      { "<leader>oe", "<cmd>Neotree toggle<cr>",                                    desc = "Explorer (Root Dir)" },
      { "<leader>oE", "<cmd>Neotree toggle cwd=<cwd><cr>",                          desc = "Explorer (cwd)" },

      -- New <leader>o group — session/quit entries (auto-session)
      { "<leader>oq", "<cmd>qa<cr>",                                                   desc = "Quit All" },
      { "<leader>os", function() require("auto-session").restore() end,                 desc = "Restore Session" },
      { "<leader>oS", function() require("auto-session.session").search_session() end, desc = "Select Session" },
      { "<leader>ol", function() require("auto-session").restore("last") end,            desc = "Restore Last Session" },
      { "<leader>oD", function() require("auto-session").disable() end,                  desc = "Don't Save Current Session" },
    },
  },

  -- ── Override snacks picker keybindings (in case it's the active picker) ──
  --
  -- Same approach: disable ALL <leader>f* and <leader>q* sub-keys.
  {
    "folke/snacks.nvim",
    optional = true,
    keys = {
      -- New direct shortcuts
      { "<leader>f",  function() Snacks.picker.files() end,                        desc = "Find Files (Root Dir)", mode = "n" },
      { "<leader>F",  function() Snacks.picker.grep() end,                         desc = "Grep (Root Dir)",        mode = "n" },

      -- Disable ALL old <leader>f* sub-keys
      { "<leader>ff", false },
      { "<leader>fF", false },
      { "<leader>fb", false },
      { "<leader>fB", false },
      { "<leader>fc", false },
      { "<leader>fg", false },
      { "<leader>fr", false },
      { "<leader>fR", false },
      { "<leader>fp", false },
      { "<leader>fn", false },
      { "<leader>fe", false },
      { "<leader>fE", false },
      { "<leader>ft", false },
      { "<leader>fT", false },

      -- Disable old <leader>sg and <leader>/ (replaced by <leader>F)
      { "<leader>sg", false },
      { "<leader>/",  false },

      -- New <leader>o group — file/find entries (moved from <leader>f)
      { "<leader>of", function() Snacks.picker.files() end,                                     desc = "Find Files (Root Dir)" },
      { "<leader>oF", function() Snacks.picker.files({ cwd = vim.uv.cwd() }) end,               desc = "Find Files (cwd)" },
      { "<leader>ob", function() Snacks.picker.buffers() end,                                    desc = "Buffers" },
      { "<leader>oB", function() Snacks.picker.buffers({ hidden = true, nofile = true }) end,  desc = "Buffers (all)" },
      { "<leader>oc", LazyVim.pick.config_files(),                                                desc = "Find Config File" },
      { "<leader>og", function() Snacks.picker.git_files() end,                                  desc = "Git Files" },
      { "<leader>or", function() Snacks.picker.recent() end,                                     desc = "Recent" },
      { "<leader>oR", function() Snacks.picker.recent({ filter = { cwd = true } }) end,        desc = "Recent (cwd)" },
      { "<leader>op", function() Snacks.picker.projects() end,                                    desc = "Projects" },
      { "<leader>oe", "<cmd>Neotree toggle<cr>",                                               desc = "Explorer (Root Dir)" },
      { "<leader>oE", "<cmd>Neotree toggle cwd=<cwd><cr>",                                     desc = "Explorer (cwd)" },

      -- New <leader>o group — session/quit entries (auto-session)
      { "<leader>oq", "<cmd>qa<cr>",                                                   desc = "Quit All" },
      { "<leader>os", function() require("auto-session").restore() end,                 desc = "Restore Session" },
      { "<leader>oS", function() require("auto-session.session").search_session() end, desc = "Select Session" },
      { "<leader>ol", function() require("auto-session").restore("last") end,            desc = "Restore Last Session" },
      { "<leader>oD", function() require("auto-session").disable() end,                  desc = "Don't Save Current Session" },
    },
  },

  -- ── Move grug-far's openLocation off <leader>o (conflicts with our "open" group) ──
  {
    "MagicDuck/grug-far.nvim",
    optional = true,
    opts = {
      keymaps = {
        openLocation = { n = "<leader>go" }, -- was <leader>o → now <leader>go
        -- Also move qflist off <leader>q since <leader>q is now Quit All
        -- (grug-far buffer-local, so it won't conflict globally, but let's
        -- move it to <leader>gq for consistency)
        qflist = { n = "<leader>gq" }, -- was <leader>q → now <leader>gq
      },
    },
  },

  -- ── Override neo-tree: disable <leader>fe/<leader>fE, remap <leader>e to <leader>oe ─
  --
  -- <leader>fe/<leader>fE MUST be disabled or <leader>f still acts as a group.
  -- We move the explorer to <leader>oe/<leader>oE and keep <leader>e as a
  -- direct shortcut to the explorer (same behaviour as before, just remapped).
  {
    "nvim-neo-tree/neo-tree.nvim",
    optional = true,
    keys = {
      { "<leader>fe", false },
      { "<leader>fE", false },
      { "<leader>e",  "<leader>oe", desc = "Explorer NeoTree (Root Dir)", remap = true },
      { "<leader>E",  "<leader>oE", desc = "Explorer NeoTree (cwd)",      remap = true },
    },
  },
}