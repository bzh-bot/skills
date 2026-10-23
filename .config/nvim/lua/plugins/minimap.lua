-- Code minimap: mini.map (float-only). History: neominimap (coroutine races at
-- the time), codewindow.nvim (depends on nvim-treesitter.ts_utils, removed in
-- nvim-treesitter v1 which LazyVim ships), minimap.vim (real split worked but
-- its render pipeline fought this config's plugin stack — removed).
-- mini.map is from the mini.nvim family — zero dependencies, and it just works.
--
-- DEFAULT OFF: the old auto-open autocmds are gone on purpose. Toggle manually.
--
-- Keymap:
--   <leader>um  toggle minimap window
--   <leader>uM  toggle focus into minimap (jump cursor in/out)
--   <leader>uR  toggle minimap side (left/right)
return {
  -- Disable the abandoned plugins so :Lazy clean removes them
  { "Isrothy/neominimap.nvim", enabled = false },
  { "gorbit99/codewindow.nvim", enabled = false },
  { "wfxr/minimap.vim", enabled = false },

  {
    "nvim-mini/mini.map",
    version = "*",
    event = "VeryLazy",
    keys = {
      { "<leader>um", function() require("mini.map").toggle() end,        desc = "Toggle Minimap" },
      { "<leader>uM", function() require("mini.map").toggle_focus() end, desc = "Toggle Minimap Focus" },
      { "<leader>uR", function() require("mini.map").toggle_side() end,   desc = "Toggle Minimap Side" },
    },
    config = function()
      local map = require("mini.map")
      map.setup({
        -- What to render as the minimap content
        symbols = {
          encode = map.gen_encode_symbols.dot("4x2"),  -- braille-style 2x4 dots, dense and crisp
          scroll_line = "█",
          scroll_view = "┃",
        },
        -- Side panels: diagnostics, git status, search hits, test coverage
        integrations = {
          map.gen_integration.builtin_search(),
          map.gen_integration.diagnostic({
            error = "DiagnosticFloatingError",
            warn  = "DiagnosticFloatingWarn",
            info  = "DiagnosticFloatingInfo",
            hint  = "DiagnosticFloatingHint",
          }),
          map.gen_integration.gitsigns(),
          require("config.coverage").minimap_integration({
            covered   = "CoverageCoveredLine",
            uncovered = "CoverageUncoveredLine",
          }),
        },
        window = {
          side = "right",
          width = 12,
          winblend = 25,    -- slight transparency
          show_integration_count = false,
          focusable = true,
          zindex = 10,
        },
      })
      -- No auto-open: opening a file leaves the minimap off until toggled.
    end,
  },
}