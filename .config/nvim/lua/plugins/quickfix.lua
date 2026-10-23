-- nvim-bqf: better quickfix window with preview, fuzzy filter, and "signs"
-- (the checkmark/select system) for trimming results from a search before acting.
--
-- The flow you want:
--   1. Run a search (`<leader>/`, `gr`, `<M-g>`, etc.) — results land in qflist
--   2. Open quickfix (`<leader>xQ` or `:copen`)
--   3. In the quickfix window, press <Tab> on items you want to KEEP — a sign
--      (the "checkmark") appears. <S-Tab> in visual mode toggles a range.
--   4. Press `zn` to keep ONLY signed items (drops the rest from qflist),
--      or `zN` to keep only UNSIGNED items (deletes the signed ones).
--   5. `zf` opens a fuzzy filter to narrow further.
--   6. Press `p` to preview an item without jumping. `P` toggles auto-preview.
--   7. `<CR>` jumps to the item as usual.
--
-- Bonus: also installs `nvim-pqf` for prettier qflist formatting (icons,
-- aligned columns, syntax-highlighted line text).
return {
  {
    "kevinhwang91/nvim-bqf",
    ft = "qf",
    opts = {
      auto_enable = true,
      auto_resize_height = true,
      preview = {
        win_height = 15,
        win_vheight = 15,
        delay_syntax = 50,
        border = "rounded",
        show_title = true,
        should_preview_cb = function(bufnr)
          -- Skip preview for huge files or non-files
          local fsize = vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr))
          return fsize <= 500 * 1024 -- 500KB
        end,
      },
      func_map = {
        -- Defaults are mostly good; a few sensible tweaks:
        vsplit = "",         -- bqf's default <C-x>/<C-v>/<C-t> already work
        ptogglemode = "z,",  -- toggle preview window resize mode
        stoggleup = "<S-Tab>",
        stoggledown = "<Tab>",
        stogglevm = "<Tab>",
        filter = "zn",       -- keep only signed
        filterr = "zN",      -- keep only UNsigned (i.e. delete signed)
        fzffilter = "zf",    -- fuzzy-filter via fzf
      },
      filter = {
        fzf = {
          action_for = {
            ["ctrl-s"] = "split",
            ["ctrl-v"] = "vsplit",
            ["ctrl-t"] = "tab drop",
            ["ctrl-q"] = "signtoggle",
          },
          extra_opts = { "--bind", "ctrl-o:toggle-all", "--prompt", "❯ " },
        },
      },
    },
  },

  -- Prettier quickfix display (icons + aligned + syntax-highlighted text).
  -- Pure visual upgrade, doesn't change behavior.
  {
    "yorickpeterse/nvim-pqf",
    event = "VeryLazy",
    opts = {
      signs = {
        error = { text = "", hl = "DiagnosticSignError" },
        warning = { text = "", hl = "DiagnosticSignWarn" },
        info = { text = "", hl = "DiagnosticSignInfo" },
        hint = { text = "", hl = "DiagnosticSignHint" },
      },
      show_multiple_lines = false,
      max_filename_length = 60,
    },
  },
}
