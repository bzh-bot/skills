-- Smooth scrolling & cursor movement.
--   • snacks.scroll  — animates <C-d>/<C-u>/zz/n/N/gg/G and similar jumps
--   • smear-cursor   — VSCode-ish trailing "smear" when the cursor leaps
return {
  -- snacks is already loaded by LazyVim; we're just turning on the scroll module.
  {
    "folke/snacks.nvim",
    opts = {
      scroll = {
        enabled = true,
        animate = {
          duration = { step = 15, total = 200 }, -- ms; lower = snappier
          easing = "linear",
        },
        -- Don't animate inside terminals, prompts, big files, etc.
        filter = function(buf)
          return vim.g.snacks_scroll ~= false
            and vim.b[buf].snacks_scroll ~= false
            and vim.bo[buf].buftype ~= "terminal"
        end,
      },
    },
  },

  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    opts = {
      -- Speed/feel
      stiffness = 0.8,             -- 0.0 (floaty) .. 1.0 (instant). 0.8 = quick & snappy
      trailing_stiffness = 0.5,    -- tail catches up a bit slower than the head
      damping = 0.8,
      matrix_pixel_threshold = 0.5,
      -- Only smear on bigger jumps; tiny moves stay instant
      min_horizontal_distance_smear = 1,
      min_vertical_distance_smear = 2,
      -- Don't smear inside terminal / cmdline
      smear_between_buffers = true,
      smear_between_neighbor_lines = true,
      smear_to_cmd = false,
      -- Auto-pick color from the current Cursor highlight; comment out if you
      -- want to hard-code one (e.g. cursor_color = "#AEAFAD" to match capo-dark)
      -- cursor_color = "#AEAFAD",
    },
  },
}
